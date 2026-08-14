(define-module (tests test-production-processors)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-64)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-process)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia cognitive-state)
  #:use-module (gaia production-processors))

(test-begin "gaia-production-processors")

(test-assert "production processors drive solve through the Cognitive Bus"
  (let ((session (make-cognitive-session #:workspace-capacity 8))
        (client-events '())
        (finished #f)
        (generated-prompts '()))
    (let ((process
           (start-production-process!
            session "Evaluate a deterministic expression"
            #:generate
            (lambda (prompt succeed fail)
              (set! generated-prompts (cons prompt generated-prompts))
              (succeed "Run it:\n```repl\n(+ 20 22)\n```"))
            #:execute
            (lambda (code succeed fail)
              (if (string=? code "(+ 20 22)")
                  (succeed "42")
                  (fail 'runtime "unexpected code")))
            #:extract-action
            (lambda (response) "(+ 20 22)")
            #:on-client-event
            (lambda (event) (set! client-events (cons event client-events)))
            #:on-finished
            (lambda (outcome final-text hypothesis-text)
              (set! finished (list outcome final-text))))))
      (let* ((events (state-events (session-state session)))
             (types (map event-type events))
             (candidate-origins
              (map event-origin
                   (filter (lambda (event)
                             (eq? (event-type event) 'CandidateSubmitted))
                           events))))
        (and (not (process-active? process))
             (eq? (process-outcome process) 'INCONCLUSIVE)
             (pair? generated-prompts)
             (equal? (map car (reverse client-events)) '(code result))
             (eq? (car finished) 'INCONCLUSIVE)
             (every (lambda (origin) (memq origin candidate-origins))
                    '(MEMORY GENERATIVE PLANNER DELIBERATIVE))
             (every (lambda (required) (memq required types))
                    '(ObservationReceived GoalCreated MemoryRetrieved
                      HypothesisProposed ActionRequested ActionCompleted
                      EvidenceFound BeliefUpdated ReflectionRaised
                      AnswerRequested ProcessTerminated)))))))

(test-assert "an unexecutable hypothesis terminates once without calling execution"
  (let ((session (make-cognitive-session #:workspace-capacity 8))
        (execution-calls 0)
        (finishes '()))
    (start-production-process!
     session "Answer without executable evidence"
     #:generate (lambda (prompt succeed fail) (succeed "A tentative answer"))
     #:execute (lambda (code succeed fail)
                 (set! execution-calls (+ execution-calls 1)))
     #:extract-action (lambda (response) #f)
     #:on-finished
     (lambda (outcome final-text hypothesis-text)
       (set! finishes (cons outcome finishes))))
    (let ((terminals
           (filter (lambda (event)
                     (memq (event-type event) '(GoalCompleted ProcessTerminated)))
                   (state-events (session-state session)))))
      (and (= execution-calls 0)
           (equal? finishes '(INSUFFICIENT_INFORMATION))
           (= (length terminals) 1)
           (eq? (event-payload (car terminals)) 'INSUFFICIENT_INFORMATION)))))

(test-assert "interruption terminates once and ignores a late Generative callback"
  (let ((session (make-cognitive-session #:workspace-capacity 8))
        (late-success #f)
        (finishes 0))
    (start-production-process!
     session "Wait for a delayed model"
     #:generate (lambda (prompt succeed fail) (set! late-success succeed))
     #:execute (lambda (code succeed fail) (succeed "unexpected"))
     #:extract-action (lambda (response) "(+ 1 1)")
     #:on-finished (lambda args (set! finishes (+ finishes 1))))
    (session-request-interrupt! session)
    (late-success "Late response\n```repl\n(+ 1 1)\n```")
    (let* ((events (state-events (session-state session)))
           (terminals (filter (lambda (event)
                                (memq (event-type event)
                                      '(GoalCompleted ProcessTerminated)))
                              events)))
      (and (= finishes 0)
           (= (length terminals) 1)
           (eq? (event-payload (car terminals)) 'USER_INTERRUPTED)
           (not (memq 'HypothesisProposed (map event-type events)))))))

(test-end "gaia-production-processors")
