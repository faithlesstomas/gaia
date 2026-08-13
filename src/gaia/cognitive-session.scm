(define-module (gaia cognitive-session)
  #:use-module (srfi srfi-9)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-state)
  #:use-module (gaia workspace)
  #:use-module (gaia cognitive-control)
  #:export (<cognitive-session>
            make-cognitive-session
            cognitive-session?
            session-state
            session-workspace
            session-bus
            session-control
            session-submit!
            session-advance!
            session-record-result!
            session-record-failure!))

;; This is the minimal GCAS process coordinator.  It deliberately does not call
;; an LLM or a REPL: processors are attached through bus subscriptions and make
;; their own proposals.  That keeps cognition separate from any one processor.
(define-record-type <cognitive-session>
  (%make-session state workspace bus control)
  cognitive-session?
  (state session-state)
  (workspace session-workspace)
  (bus session-bus)
  (control session-control))

(define* (make-cognitive-session #:key (workspace-capacity 7) (max-transitions 32))
  (%make-session (make-cognitive-state)
                 (make-global-workspace #:capacity workspace-capacity)
                 (make-cognitive-bus)
                 (make-cognitive-control #:max-transitions max-transitions)))

(define (emit! session event)
  (state-record-event! (session-state session) event)
  (bus-publish (session-bus session) event))

(define* (session-submit! session co #:key (priority 0) (origin 'KERNEL))
  (state-store! (session-state session) co)
  (workspace-propose! (session-workspace session) co #:priority priority)
  (emit! session (make-cognitive-event 'CandidateSubmitted co #:origin origin))
  co)

(define (session-advance! session)
  (let ((reason (control-termination-reason (session-control session))))
    (if reason
        (emit! session (make-cognitive-event 'ProcessTerminated reason #:origin 'CONTROL))
        (let ((admitted (workspace-admit-next! (session-workspace session))))
          (and admitted
               (begin
                 (control-record-transition! (session-control session))
                 (emit! session (make-cognitive-event 'WorkspaceBroadcast admitted #:origin 'WORKSPACE))
                 admitted))))))

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
