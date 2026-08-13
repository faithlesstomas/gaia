(define-module (tests test-cognitive-session)
  #:use-module (srfi srfi-64)
  #:use-module (srfi srfi-1)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia cognitive-control)
  #:use-module (gaia cognitive-state)
  #:use-module (gaia workspace)
  #:use-module (gaia cognitive-processor))

(test-begin "gaia-cognitive-session")

(test-group "state-workspace-control-cycle"
  (test-assert "proposal is stored but not broadcast before selective admission"
    (let* ((session (make-cognitive-session #:workspace-capacity 1))
           (goal (make-cognitive-object 'goal "Inspect evidence" #:provenance 'USER)))
      (session-submit! session goal #:priority 5 #:origin 'USER)
      (and (state-has-object? (session-state session) (co-id goal))
           (= (length (workspace-candidates (session-workspace session))) 1)
           (null? (workspace-active (session-workspace session)))
           (= (length (state-events (session-state session))) 1))))

  (test-assert "highest priority candidate is admitted and broadcast"
    (let* ((session (make-cognitive-session #:workspace-capacity 2))
           (low (make-cognitive-object 'question "Low urgency" #:provenance 'USER))
           (high (make-cognitive-object 'goal "High urgency" #:provenance 'USER)))
      (session-submit! session low #:priority 1 #:origin 'USER)
      (session-submit! session high #:priority 9 #:origin 'USER)
      (let ((admitted (session-advance! session)))
        (and (equal? (co-id admitted) (co-id high))
             (equal? (co-id (car (workspace-active (session-workspace session)))) (co-id high))))))

  (test-assert "only an explicit Action CO can receive a runtime result"
    (let* ((session (make-cognitive-session))
           (action (make-cognitive-object 'action "Run observation" #:provenance 'LLM))
           (result (make-cognitive-object 'result "Observed output" #:provenance 'REPL)))
      (session-submit! session action #:origin 'LLM)
      (session-record-result! session (co-id action) result)
      (and (state-has-object? (session-state session) (co-id result))
           (eq? (event-type (last (state-events (session-state session)))) 'ActionCompleted)))) )

(test-group "bounded-progress"
  (test-equal "control stops admissions after configured transition budget"
    'BUDGET_EXHAUSTED
    (let* ((session (make-cognitive-session #:max-transitions 1))
           (first (make-cognitive-object 'goal "First" #:provenance 'USER))
           (second (make-cognitive-object 'goal "Second" #:provenance 'USER)))
      (session-submit! session first #:origin 'USER)
      (session-submit! session second #:origin 'USER)
      (session-advance! session)
      (session-advance! session)
      (event-payload (last (state-events (session-state session)))))))

(test-group "workspace-policy-and-processors"
  (test-assert "control selects the safer, more relevant candidate and enforces workspace capacity"
    (let* ((session (make-cognitive-session #:workspace-capacity 1))
           (risky (make-cognitive-object 'action "Network-wide destructive scan" #:provenance 'LLM))
           (useful (make-cognitive-object 'action "Read the goal-local evidence" #:provenance 'LLM)))
      (session-submit! session risky #:priority 100 #:risk 1 #:cost 1 #:uncertainty 1 #:origin 'PLANNER)
      (session-submit! session useful #:priority 85 #:relevance 1 #:origin 'PLANNER)
      (let ((first (session-advance! session)))
        (and (equal? (co-id first) (co-id useful))
             (not (session-advance! session))
             (= (length (workspace-candidates (session-workspace session))) 1)
             (session-release-workspace-object! session (co-id first))
             (equal? (co-id (session-advance! session)) (co-id risky))))))

  (test-assert "an event-driven processor submits a candidate instead of broadcasting directly"
    (let* ((session (make-cognitive-session #:workspace-capacity 2))
           (planner
            (make-cognitive-processor
             'PLANNER '(GoalCreated)
             (lambda (event)
               (let ((goal (event-payload event)))
                 (list (make-processor-proposal
                        (make-cognitive-object 'plan "Inspect executable evidence"
                                               #:provenance 'SYMBOLIC_INFERENCE
                                               #:relations `((serves . ,(co-id goal))))
                        #:priority 80 #:relevance 1))))))
           (goal (make-cognitive-object 'goal "Verify a runtime result" #:provenance 'USER)))
      (attach-processor! session planner)
      (session-submit! session goal #:priority 100 #:origin 'USER)
      (session-emit! session 'GoalCreated goal #:origin 'CONTROL)
      (let ((plans (filter (lambda (co) (eq? (co-type co) 'plan))
                           (workspace-candidates (session-workspace session)))))
        (and (= (length plans) 1)
             (not (member 'WorkspaceBroadcast
                          (map event-type (state-events (session-state session)))))
             (eq? (co-provenance (car plans)) 'SYMBOLIC_INFERENCE)))))

  (test-assert "terminal cleanup releases capacity without deleting the cognitive record"
    (let* ((session (make-cognitive-session #:workspace-capacity 1))
           (goal (make-cognitive-object 'goal "Complete a bounded process" #:provenance 'USER)))
      (session-submit! session goal #:priority 100 #:origin 'USER)
      (session-advance! session)
      (session-clear-workspace! session)
      (and (null? (workspace-active (session-workspace session)))
           (state-has-object? (session-state session) (co-id goal))))))

  (test-assert "state, event log, and reproducibility record survive session restoration"
    (let* ((path "/tmp/gaia-gcas-state-test.scm")
           (_ (when (file-exists? path) (delete-file path)))
           (session (make-cognitive-session #:state-path path))
           (action (make-cognitive-object 'action "(+ 20 22)" #:provenance 'LLM))
           (result (make-cognitive-object 'result "42" #:provenance 'REPL
                                          #:relations `((produced-by . ,(co-id action))))))
      (session-submit! session action #:priority 90 #:origin 'CONTROL)
      (session-advance! session)
      (session-record-result! session (co-id action) result #:environment "test-runtime")
      (let* ((restored (make-cognitive-session #:state-path path))
             (objects (state-objects (session-state restored))))
        (delete-file path)
        (and (state-has-object? (session-state restored) (co-id result))
             (member 'ActionCompleted (map event-type (state-events (session-state restored))))
             (= (length (filter (lambda (co) (eq? (co-type co) 'observation)) objects)) 1)))))

  (test-assert "an explicitly cleared durable session does not restore old state"
    (let* ((path "/tmp/gaia-gcas-cleared-state-test.scm")
           (_ (when (file-exists? path) (delete-file path)))
           (original (make-cognitive-session #:state-path path))
           (goal (make-cognitive-object 'goal "Old goal" #:provenance 'USER)))
      (session-submit! original goal #:origin 'USER)
      (let ((cleared (make-cognitive-session #:state-path path #:restore? #f)))
        (delete-file path)
        (and (null? (state-objects (session-state cleared)))
             (null? (state-events (session-state cleared)))))))

  (test-assert "control records execution progress, failure budgets, and user interruption"
    (let* ((session (make-cognitive-session #:max-transitions 10))
           (action (make-cognitive-object 'action "(+ 1 1)" #:provenance 'LLM))
           (result (make-cognitive-object 'result "2" #:provenance 'REPL
                                          #:relations `((produced-by . ,(co-id action))))))
      (session-submit! session action #:origin 'CONTROL)
      (session-advance! session)
      (session-record-result! session (co-id action) result)
      (and (= (control-progress-count (session-control session)) 1)
           (eq? (session-request-interrupt! session) 'USER_INTERRUPTED)
           (eq? (control-termination-reason (session-control session)) 'USER_INTERRUPTED))))

(test-end "gaia-cognitive-session")
