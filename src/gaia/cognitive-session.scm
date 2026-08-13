(define-module (gaia cognitive-session)
  #:use-module (srfi srfi-9)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-state)
  #:use-module (gaia workspace)
  #:use-module (gaia cognitive-control)
  #:use-module (gaia cognitive-memory)
  #:export (<cognitive-session>
            make-cognitive-session
            cognitive-session?
            session-state
            session-workspace
            session-bus
            session-control
            session-memory
            session-submit!
            session-advance!
            session-emit!
            session-release-workspace-object!
            session-clear-workspace!
            session-record-result!
            session-record-failure!))

;; This is the minimal GCAS process coordinator.  It deliberately does not call
;; an LLM or a REPL: processors are attached through bus subscriptions and make
;; their own proposals.  That keeps cognition separate from any one processor.
(define-record-type <cognitive-session>
  (%make-session state workspace bus control memory)
  cognitive-session?
  (state session-state)
  (workspace session-workspace)
  (bus session-bus)
  (control session-control)
  (memory session-memory))

(define* (make-cognitive-session #:key (workspace-capacity 7) (max-transitions 32) (memory-path #f))
  (%make-session (make-cognitive-state)
                 (make-global-workspace #:capacity workspace-capacity)
                 (make-cognitive-bus)
                 (make-cognitive-control #:max-transitions max-transitions)
                 (make-cognitive-memory #:path memory-path)))

(define (emit! session event)
  (state-record-event! (session-state session) event)
  (bus-publish (session-bus session) event))

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
        (emit! session (make-cognitive-event 'ProcessTerminated reason #:origin 'CONTROL))
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

(define (session-release-workspace-object! session object-id)
  "Remove a processed object from bounded active workspace without deleting it
from Cognitive State."
  (workspace-retract! (session-workspace session) object-id))

(define (session-clear-workspace! session)
  "Release all active COs at a terminal boundary while preserving State and
Memory. A later goal reconstructs its own bounded working set from them."
  (for-each (lambda (co) (workspace-retract! (session-workspace session) (co-id co)))
            (workspace-active (session-workspace session)))
  'ok)

(define (session-record-result! session action-id result-co)
  (unless (and (state-has-object? (session-state session) action-id)
               (control-action-permitted? (state-find (session-state session) action-id)))
    (error "Result must reference a permitted Action CO" action-id))
  (state-store! (session-state session) result-co)
  (emit! session (make-cognitive-event 'ActionCompleted result-co #:origin 'EXECUTION))
  result-co)

(define (session-record-failure! session action-id failure-co)
  (unless (and (state-has-object? (session-state session) action-id)
               (control-action-permitted? (state-find (session-state session) action-id)))
    (error "Failure must reference a permitted Action CO" action-id))
  (state-store! (session-state session) failure-co)
  (emit! session (make-cognitive-event 'ActionFailed failure-co #:origin 'EXECUTION))
  failure-co)
