(define-module (gaia cognitive-session)
  #:use-module (srfi srfi-9)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-state)
  #:use-module (gaia workspace)
  #:use-module (gaia cognitive-control)
  #:use-module (gaia cognitive-process)
  #:use-module (gaia cognitive-memory)
  #:export (<cognitive-session>
            make-cognitive-session
            cognitive-session?
            session-state
            session-workspace
            session-bus
            session-control
            session-current-process
            session-start-process!
            session-finish-process!
            session-complete-goal!
            session-memory
            session-state-path
            session-persist!
            session-submit!
            session-advance!
            session-run-workspace-round!
            session-emit!
            session-release-workspace-object!
            session-clear-workspace!
            session-request-interrupt!
            session-record-result!
            session-record-failure!))

;; This is the minimal GCAS process coordinator.  It deliberately does not call
;; an LLM or a REPL: processors are attached through bus subscriptions and make
;; their own proposals.  That keeps cognition separate from any one processor.
(define-record-type <cognitive-session>
  (%make-session state workspace bus fallback-control memory state-path current-process-cell)
  cognitive-session?
  (state session-state)
  (workspace session-workspace)
  (bus session-bus)
  (fallback-control session-fallback-control)
  (memory session-memory)
  (state-path session-state-path)
  (current-process-cell session-current-process-cell))

(define* (make-cognitive-session #:key (workspace-capacity 7) (max-transitions 32)
                                (memory-path #f) (state-path #f) (restore? #t))
  (let ((session
         (%make-session (if (and state-path restore?)
                            (load-cognitive-state state-path)
                            (make-cognitive-state))
                        (make-global-workspace #:capacity workspace-capacity)
                        (make-cognitive-bus)
                        (make-cognitive-control #:max-transitions max-transitions)
                        (make-cognitive-memory #:path memory-path #:restore? restore?)
                        state-path
                        (list #f))))
    ;; Start an explicitly cleared session with an empty, durable state rather
    ;; than letting an old audit graph be restored later.
    (when (and state-path (not restore?))
      (session-persist! session))
    session))

(define (session-current-process session)
  (car (session-current-process-cell session)))

(define (session-control session)
  (let ((process (session-current-process session)))
    (if (and process (process-active? process))
        (process-control process)
        (session-fallback-control session))))

(define* (session-start-process! session goal completion-criteria
                                 #:key
                                 (max-transitions 32)
                                 (max-stalled-transitions 8)
                                 (max-failures 3))
  "Start one isolated Goal lifecycle. A session may have at most one active
process, but retains every previous Goal and terminal event for audit."
  (let ((current (session-current-process session)))
    (when (and current (process-active? current))
      (error "Cannot start a second Cognitive Process while one is active"
             (process-id current))))
  (let ((process (make-cognitive-process
                  goal completion-criteria
                  #:max-transitions max-transitions
                  #:max-stalled-transitions max-stalled-transitions
                  #:max-failures max-failures)))
    (set-car! (session-current-process-cell session) process)
    process))

(define (session-finish-process! session outcome)
  "Finish the active process exactly once and emit its durable terminal event."
  (when (eq? outcome 'COMPLETED)
    (error "Goal completion requires session-complete-goal! with verified evidence"))
  (let ((process (session-current-process session)))
    (and process
         (process-finish! process outcome)
         (begin
           (emit! session
                  (make-cognitive-event
                   (if (eq? outcome 'COMPLETED) 'GoalCompleted 'ProcessTerminated)
                   (if (eq? outcome 'COMPLETED) (process-goal process) outcome)
                   #:origin 'CONTROL))
           (session-clear-workspace! session)
           outcome))))

(define (session-complete-goal! session verified-claim)
  "Complete the active Goal only from an accepted, verified Claim that explicitly
satisfies it.  This is the sole production path to GoalCompleted."
  (let ((process (session-current-process session)))
    (unless (and process (process-active? process)
                 (fact? verified-claim)
                 (memq (co-provenance verified-claim)
                       '(SYMBOLIC_INFERENCE FORMAL_PROOF))
                 (assoc-ref (co-relations verified-claim) 'supported-by)
                 (equal? (assoc-ref (co-relations verified-claim) 'satisfies)
                         (co-id (process-goal process))))
      (error "Goal completion requires a verified Claim satisfying the active Goal"
             verified-claim))
    (and (process-finish! process 'COMPLETED)
         (begin
           (state-store! (session-state session) verified-claim)
           (emit! session
                  (make-cognitive-event 'GoalCompleted (process-goal process)
                                        #:origin 'GOAL_VERIFIER))
           (session-clear-workspace! session)
           'COMPLETED))))

(define (session-persist! session)
  (let ((path (session-state-path session)))
    (when path
      (save-cognitive-state! (session-state session) path))
    path))

(define (emit! session event)
  (state-record-event! (session-state session) event)
  (bus-publish (session-bus session) event)
  (session-persist! session)
  event)

(define* (session-emit! session type payload #:key (origin 'KERNEL))
  "Record and broadcast a semantic state-change event."
  (emit! session (make-cognitive-event type payload #:origin origin)))

(define* (session-submit! session co
                         #:key
                         (priority 0)
                         (relevance 0)
                         (risk 0)
                         (cost 0)
                         (uncertainty 0)
                         (origin 'KERNEL))
  (state-store! (session-state session) co)
  (workspace-propose! (session-workspace session) co
                      #:priority priority
                      #:relevance relevance
                      #:risk risk
                      #:cost cost
                      #:uncertainty uncertainty)
  (emit! session (make-cognitive-event 'CandidateSubmitted co #:origin origin))
  co)

(define (session-advance! session)
  (let ((reason (control-termination-reason (session-control session))))
    (if reason
        (or (session-finish-process! session reason)
            (emit! session (make-cognitive-event 'ProcessTerminated reason #:origin 'CONTROL)))
        (let ((admitted (workspace-admit-next!
                         (session-workspace session)
                         #:selector (lambda (candidates)
                                      (control-select-candidate
                                       (session-control session)
                                       candidates)))))
          (and admitted
               (begin
                 (control-record-transition! (session-control session))
                 (emit! session (make-cognitive-event 'WorkspaceBroadcast admitted #:origin 'WORKSPACE))
                 admitted))))))

(define (workspace-round-payload session candidates admitted)
  `((process-id . ,(let ((process (session-current-process session)))
                     (and process (process-id process))))
    (candidate-count . ,(length candidates))
    (candidate-ids . ,(map (lambda (entry) (co-id (candidate-co entry))) candidates))
    (winner . ,(and admitted (co-id admitted)))))

(define (session-run-workspace-round! session)
  "Run one explicit Workspace competition round.

All pending proposals are visible to Control before one is admitted.  The
admitted CO is broadcast synchronously, then released from active Workspace
focus while its durable Cognitive State record remains available to processors.
This makes the Workspace a bounded, dynamic broadcast process rather than a
growing execution history."
  (let ((candidates (workspace-candidate-entries (session-workspace session))))
    (and (pair? candidates)
         (begin
           (session-emit! session 'WorkspaceRoundStarted
                          (workspace-round-payload session candidates #f)
                          #:origin 'CONTROL)
           (let ((admitted (session-advance! session)))
             (when admitted
               (session-release-workspace-object! session (co-id admitted)))
             (session-emit! session 'WorkspaceRoundCompleted
                            (workspace-round-payload session candidates admitted)
                            #:origin 'CONTROL)
             admitted)))))

(define (session-release-workspace-object! session object-id)
  "Remove a processed object from bounded active workspace without deleting it
from Cognitive State."
  (workspace-retract! (session-workspace session) object-id))

(define (session-clear-workspace! session)
  "Release active and pending COs at a terminal boundary while preserving
State and Memory. No proposal from a completed process may compete in the next."
  (workspace-clear! (session-workspace session)))

(define (session-request-interrupt! session)
  "Let cognitive control terminate the active process on an explicit user stop."
  (let ((reason (control-request-interrupt! (session-control session))))
    (if (and (session-current-process session)
             (process-active? (session-current-process session)))
        (session-finish-process! session reason)
        (begin
          (emit! session (make-cognitive-event 'ProcessTerminated reason #:origin 'CONTROL))
          (session-clear-workspace! session)))
    reason))

(define (make-reproducibility-record session action-id result-co outcome environment)
  (let ((action-co (state-find (session-state session) action-id)))
    (make-cognitive-object
     'observation
     `((action-id . ,action-id)
       (action-payload . ,(co-content action-co))
       (outcome . ,outcome)
       (output . ,(co-content result-co))
       (runtime . ,environment)
       (environment-hash . ,(number->string (hash environment 4294967295) 16))
       (dependencies . ())
       (parameters . ,(co-relations action-co))
       (output-hash . ,(number->string
                        (hash (format #f "~s" (co-content result-co)) 4294967295)
                        16))
       (recorded-at . ,(current-time)))
     #:provenance 'EXECUTION
     #:relations `((reproduces . ,action-id)
                   (observes . ,(co-id result-co))))))

(define* (session-record-result! session action-id result-co #:key (environment "Guile sandbox"))
  (unless (and (state-has-object? (session-state session) action-id)
               (control-action-permitted? (state-find (session-state session) action-id)))
    (error "Result must reference a permitted Action CO" action-id))
  (state-store! (session-state session) result-co)
  (state-store! (session-state session)
                (make-reproducibility-record session action-id result-co 'SUCCEEDED environment))
  (control-record-progress! (session-control session))
  (emit! session (make-cognitive-event 'ActionCompleted result-co #:origin 'EXECUTION))
  result-co)

(define* (session-record-failure! session action-id failure-co #:key (environment "Guile sandbox"))
  (unless (and (state-has-object? (session-state session) action-id)
               (control-action-permitted? (state-find (session-state session) action-id)))
    (error "Failure must reference a permitted Action CO" action-id))
  (state-store! (session-state session) failure-co)
  (state-store! (session-state session)
                (make-reproducibility-record session action-id failure-co 'FAILED environment))
  (control-record-failure! (session-control session))
  (emit! session (make-cognitive-event 'ActionFailed failure-co #:origin 'EXECUTION))
  failure-co)
