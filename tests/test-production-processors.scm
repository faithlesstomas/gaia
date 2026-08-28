(define-module (tests test-production-processors)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-64)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-memory)
  #:use-module (gaia cognitive-process)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia cognitive-state)
  #:use-module (gaia goal-verifier)
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

(test-assert "a deterministic Fibonacci Goal completes only after failure-first independent verification"
  (let ((session (make-cognitive-session #:workspace-capacity 2))
        (generated '())
        (executed '())
        (finished #f))
    (let ((process
           (start-production-process!
            session "Return the first eight Fibonacci terms."
            #:max-replans 2
            #:generate
            (lambda (prompt succeed fail)
              (let ((attempt (+ 1 (length generated))))
                (set! generated (append generated (list prompt)))
                (succeed (if (= attempt 1) "bad Fibonacci" "correct Fibonacci"))))
            #:extract-action
            (lambda (response)
              (if (string=? response "bad Fibonacci")
                  "(fib-first-eight-bad)"
                  "(fib-first-eight-correct)"))
            #:execute
            (lambda (code succeed fail)
              (set! executed (append executed (list code)))
              (succeed (if (string=? code "(fib-first-eight-bad)")
                           "0 1 2 3 5 8 13 21"
                           "0 1 1 2 3 5 8 13")))
            #:verify-goal
            (lambda (goal action result evidence execution-claim state)
              (if (string=? (co-content result) "0 1 1 2 3 5 8 13")
                  (make-goal-verdict
                   'SATISFIED
                   "The deterministic Fibonacci oracle accepted all eight terms."
                   "The first eight Fibonacci terms are 0, 1, 1, 2, 3, 5, 8, 13.")
                  (make-goal-verdict
                   'REJECTED
                   "The deterministic Fibonacci oracle rejected the execution output.")))
            #:on-finished
            (lambda (outcome final-text hypothesis-text)
              (set! finished (list outcome final-text))))))
      (let* ((events (state-events (session-state session)))
             (types (map event-type events))
             (completed-events
              (filter (lambda (event) (eq? (event-type event) 'GoalCompleted)) events))
             (verified-claims
              (filter (lambda (claim)
                        (and (fact? claim)
                             (equal? (assoc-ref (co-relations claim) 'satisfies)
                                     (co-id (process-goal process)))))
                      (state-objects (session-state session)))))
        (and (not (process-active? process))
             (eq? (process-outcome process) 'COMPLETED)
             (eq? (car finished) 'COMPLETED)
             (equal? executed '("(fib-first-eight-bad)" "(fib-first-eight-correct)"))
             (= (length generated) 2)
             (= (length completed-events) 1)
             (not (memq 'ProcessTerminated types))
             (= (length verified-claims) 1)
             (every (lambda (required) (memq required types))
                    '(ActionCompleted GoalVerificationCompleted ConflictDetected
                      ReflectionRaised GoalVerified GoalCompleted AnswerRequested)))))))

(test-assert "user testimony is context but cannot bypass Goal verification"
  (let ((session (make-cognitive-session #:workspace-capacity 3))
        (generation-calls 0)
        (second-finish #f))
    (start-production-process!
     session "Mam na imię Tomasz"
     #:generate (lambda (prompt succeed fail)
                  (set! generation-calls (+ generation-calls 1))
                  (succeed "Zapamiętam tę informację."))
     #:extract-action (lambda (response) #f)
     #:execute (lambda args (error "memory assertion must not execute")))
    (let ((process
           (start-production-process!
            session "Jak mam na imię?"
            #:generate (lambda (prompt succeed fail)
                         (set! generation-calls (+ generation-calls 1))
                         (succeed "No independently verifiable action is available."))
            #:extract-action (lambda (response) #f)
            #:execute (lambda args (error "memory answer must not execute"))
            #:on-finished
            (lambda (outcome final-text hypothesis-text)
              (set! second-finish (list outcome final-text))))))
      (let ((types (map event-type (state-events (session-state session)))))
        (and (eq? (process-outcome process) 'INSUFFICIENT_INFORMATION)
             (eq? (car second-finish) 'INSUFFICIENT_INFORMATION)
             (= generation-calls 2)
             (memq 'MemoryRetrieved types)
             (not (memq 'GoalCompleted types)))))))

(test-assert "completed evidence graph and consolidated memory survive restart"
  (let* ((state-path "/tmp/gaia-production-restart-state.scm")
         (memory-path "/tmp/gaia-production-restart-memory.scm")
         (_ (for-each (lambda (path)
                        (when (file-exists? path) (delete-file path)))
                      (list state-path memory-path)))
         (session (make-cognitive-session #:state-path state-path
                                          #:memory-path memory-path)))
    (start-production-process!
     session "Return the first ten Fibonacci terms."
     #:completion-criteria
     (goal-completion-criteria "Return the first ten Fibonacci terms.")
     #:verify-goal
     (select-goal-verifier "Return the first ten Fibonacci terms.")
     #:generate
     (lambda (prompt succeed fail)
       (succeed "```repl\n(define (fibonacci-sequence n) '(0 1 1 2 3 5 8 13 21 34))\n(fibonacci-sequence 10)\n```"))
     #:extract-action
     (lambda (response)
       "(define (fibonacci-sequence n) '(0 1 1 2 3 5 8 13 21 34))\n(fibonacci-sequence 10)")
     #:execute (lambda (code succeed fail)
                 (succeed "(0 1 1 2 3 5 8 13 21 34)")))
    (let* ((restored (make-cognitive-session #:state-path state-path
                                             #:memory-path memory-path))
           (restored-state (session-state restored))
           (event-types (map event-type (state-events restored-state)))
           (facts (filter fact? (state-objects restored-state)))
           (memories (memory-objects (session-memory restored)))
           (procedures
            (filter (lambda (co)
                      (and (eq? (co-type co) 'procedure)
                           (eq? (memory-role co) 'PROCEDURAL)))
                    memories))
           (reused-prompt-cell (list #f))
           (reuse-process
            (start-production-process!
             restored "Reuse the verified first ten Fibonacci terms procedure."
             #:generate
             (lambda (prompt succeed fail)
               (set-car! reused-prompt-cell prompt)
               (succeed "No new Action is available for this test."))
             #:extract-action (lambda (response) #f)
             #:execute
             (lambda args
               (error "procedural retrieval must not execute by itself")))))
      (for-each (lambda (path)
                  (when (file-exists? path) (delete-file path)))
                (list state-path memory-path))
      (and (memq 'GoalVerificationCompleted event-types)
           (memq 'GoalCompleted event-types)
           (any (lambda (claim) (assoc-ref (co-relations claim) 'satisfies)) facts)
           (any fact? memories)
           (any (lambda (co) (eq? (co-type co) 'evidence)) memories)
           (any (lambda (co) (eq? (co-type co) 'result)) memories)
           (= (length procedures) 1)
           (assoc-ref (co-relations (car procedures)) 'derived-from)
           (assoc-ref (co-relations (car procedures)) 'supported-by)
           (eq? (process-outcome reuse-process) 'INSUFFICIENT_INFORMATION)
           (string-contains (car reused-prompt-cell)
                            "Verified procedure for Goal")))))

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

(test-assert "a repeated Action is detected as a loop and is not executed twice"
  (let ((session (make-cognitive-session #:workspace-capacity 2))
        (generation-calls 0)
        (execution-calls 0)
        (finished #f))
    (let ((process
           (start-production-process!
            session "Do not repeat a failed action"
            #:max-replans 1
            #:generate (lambda (prompt succeed fail)
                         (set! generation-calls (+ generation-calls 1))
                         (succeed "same proposal"))
            #:extract-action (lambda (response) "(always-fails)")
            #:execute (lambda (code succeed fail)
                        (set! execution-calls (+ execution-calls 1))
                        (fail 'runtime "repeatable failure"))
            #:on-finished (lambda (outcome final-text hypothesis-text)
                            (set! finished outcome)))))
      (let ((types (map event-type (state-events (session-state session)))))
        (and (not (process-active? process))
             (eq? finished 'FAILED)
             (= generation-calls 2)
             (= execution-calls 1)
             (memq 'ConflictDetected types)
             (memq 'ReflectionRaised types))))))

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

(test-assert "three failed Actions terminate once and notify the client"
  (let ((session (make-cognitive-session #:workspace-capacity 2))
        (generation-calls 0)
        (execution-calls 0)
        (finishes '()))
    (let ((process
           (start-production-process!
            session "Exhaust the failed-action budget"
            #:max-failures 3
            #:max-replans 3
            #:generate
            (lambda (prompt succeed fail)
              (set! generation-calls (+ generation-calls 1))
              (succeed (format #f "attempt-~a" generation-calls)))
            #:extract-action
            (lambda (response) (string-append "(" response ")"))
            #:execute
            (lambda (code succeed fail)
              (set! execution-calls (+ execution-calls 1))
              (fail 'syntax (string-append "invalid action " code)))
            #:on-finished
            (lambda (outcome final-text hypothesis-text)
              (set! finishes (cons (list outcome final-text) finishes))))))
      (let* ((events (state-events (session-state session)))
             (terminals
              (filter (lambda (event)
                        (memq (event-type event) '(GoalCompleted ProcessTerminated)))
                      events)))
        (and (not (process-active? process))
             (eq? (process-outcome process) 'FAILURE_BUDGET_EXHAUSTED)
             (= generation-calls 3)
             (= execution-calls 3)
             (= (length terminals) 1)
             (eq? (event-payload (car terminals)) 'FAILURE_BUDGET_EXHAUSTED)
             (= (length finishes) 1)
             (eq? (caar finishes) 'FAILURE_BUDGET_EXHAUSTED)
             (string-contains (cadar finishes) "failed-action budget"))))))

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
      (and (= finishes 1)
           (= (length terminals) 1)
           (eq? (event-payload (car terminals)) 'USER_INTERRUPTED)
           (not (memq 'HypothesisProposed (map event-type events)))))))

(test-end "gaia-production-processors")
