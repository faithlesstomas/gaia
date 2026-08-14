(define-module (tests test-production-processors)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-64)
  #:use-module (gaia com)
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
                      HypothesisProposed PlanProposed ActionRequested ActionCompleted
                      EvidenceFound BeliefUpdated ReflectionRaised
                      AnswerRequested ProcessTerminated
                      WorkspaceRoundStarted WorkspaceRoundCompleted)))))))

(test-assert "a failed Action feeds Reflection into a revised Plan and Action"
  (let ((session (make-cognitive-session #:workspace-capacity 2))
        (generated '())
        (executed '())
        (finished #f))
    (let ((process
           (start-production-process!
            session "Repair a failed deterministic action"
            #:max-replans 2
            #:generate
            (lambda (prompt succeed fail)
              (let ((attempt (+ 1 (length generated))))
                (set! generated (cons prompt generated))
                (succeed (if (= attempt 1) "first attempt" "revised attempt"))))
            #:extract-action
            (lambda (response)
              (if (string=? response "first attempt") "(bad-action)" "(good-action)"))
            #:execute
            (lambda (code succeed fail)
              (set! executed (append executed (list code)))
              (if (string=? code "(bad-action)")
                  (fail 'runtime "first attempt failed")
                  (succeed "verified second observation")))
            #:on-finished
            (lambda (outcome final-text hypothesis-text)
              (set! finished outcome)))))
      (let* ((events (state-events (session-state session)))
             (types (map event-type events))
             (plans (filter (lambda (co) (eq? (co-type co) 'plan))
                            (state-objects (session-state session))))
             (subgoals (filter (lambda (co)
                                (and (eq? (co-type co) 'goal)
                                     (assoc-ref (co-relations co) 'parent-goal)))
                              (state-objects (session-state session))))
             (reflections (filter (lambda (co)
                                    (and (eq? (co-type co) 'reflection)
                                         (assoc-ref (co-relations co) 'replan)))
                                  (state-objects (session-state session)))))
        (and (not (process-active? process))
             (eq? (process-outcome process) 'INCONCLUSIVE)
             (eq? finished 'INCONCLUSIVE)
             (= (length generated) 2)
             (equal? executed '("(bad-action)" "(good-action)"))
             (>= (length plans) 2)
             (>= (length subgoals) 2)
             (pair? reflections)
             (every (lambda (required) (memq required types))
                    '(ActionFailed ReflectionRaised HypothesisProposed PlanProposed
                      ActionCompleted EvidenceFound BeliefUpdated
                      WorkspaceRoundStarted WorkspaceRoundCompleted)))))))

(test-assert "a Conflict is reflected and routed to Generative replanning"
  (let ((session (make-cognitive-session #:workspace-capacity 2))
        (generation-calls 0))
    (let ((process
           (start-production-process!
            session "Resolve conflicting evidence"
            #:generate (lambda (prompt succeed fail)
                         (set! generation-calls (+ generation-calls 1)))
            #:execute (lambda (code succeed fail) (succeed "unexpected"))
            #:extract-action (lambda (response) "(unused)"))))
      (let ((conflict
             (make-cognitive-object
              'conflict "Independent evidence conflicts with the current plan."
              #:provenance 'SYMBOLIC_INFERENCE
              #:relations `((process . ,(process-id process))))))
        (session-emit! session 'ConflictDetected conflict #:origin 'DELIBERATIVE)
        (let ((types (map event-type (state-events (session-state session)))))
          (session-request-interrupt! session)
          (and (= generation-calls 2)
               (memq 'ConflictDetected types)
               (memq 'ReflectionRaised types)
               (not (process-active? process))))))))

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
