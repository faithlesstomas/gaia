(define-module (tests test-cognitive-session)
  #:use-module (srfi srfi-64)
  #:use-module (srfi srfi-1)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia cognitive-control)
  #:use-module (gaia cognitive-process)
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

(test-group "per-goal-process-lifecycle"
  (test-assert "each Goal receives an isolated Control budget"
    (let* ((session (make-cognitive-session #:max-transitions 99))
           (first-goal (make-cognitive-object 'goal "First process" #:provenance 'USER))
           (first (session-start-process! session first-goal "Complete the first process"
                                          #:max-transitions 1)))
      (session-submit! session first-goal #:origin 'USER)
      (session-advance! session)
      (let ((first-count (control-transition-count (process-control first))))
        (session-finish-process! session 'INCONCLUSIVE)
        (let* ((second-goal (make-cognitive-object 'goal "Second process" #:provenance 'USER))
               (second (session-start-process! session second-goal "Complete the second process"
                                               #:max-transitions 3)))
          (and (= first-count 1)
               (= (control-transition-count (process-control second)) 0)
               (not (eq? (process-control first) (process-control second))))))))

  (test-assert "a process emits exactly one terminal event"
    (let* ((session (make-cognitive-session))
           (goal (make-cognitive-object 'goal "Exactly once" #:provenance 'USER)))
      (session-start-process! session goal "Emit one terminal outcome")
      (session-finish-process! session 'FAILED)
      (let ((second-result (session-finish-process! session 'INCONCLUSIVE))
            (terminals (filter (lambda (event)
                                 (memq (event-type event) '(GoalCompleted ProcessTerminated)))
                               (state-events (session-state session)))))
        (and (not second-result)
             (= (length terminals) 1)
             (eq? (event-payload (car terminals)) 'FAILED))))))

  (test-assert "GoalCompleted requires a verified Claim that satisfies the active Goal"
    (let* ((session (make-cognitive-session))
           (goal (make-cognitive-object 'goal "Complete only with proof" #:provenance 'USER))
           (process (session-start-process! session goal "Verified acceptance"))
           (claim (make-cognitive-object
                   'claim "The acceptance criterion was independently met."
                   #:provenance 'SYMBOLIC_INFERENCE
                   #:epistemic-status 'ACCEPTED
                   #:verification-status 'VERIFIED
                   #:relations `((satisfies . ,(co-id goal))
                                 (supported-by . "co-independent-evidence")))))
      (and (eq? (session-complete-goal! session claim) 'COMPLETED)
           (eq? (process-outcome process) 'COMPLETED)
           (eq? (event-type (last (state-events (session-state session))))
                'GoalCompleted))))

(test-group "workspace-policy-and-processors"
  (test-assert "a Workspace round selects one competing candidate and releases its focus"
    (let* ((session (make-cognitive-session #:workspace-capacity 1))
           (low (make-cognitive-object 'hypothesis "Low priority" #:provenance 'LLM))
           (high (make-cognitive-object 'plan "High priority" #:provenance 'LLM))
           (medium (make-cognitive-object 'observation "Medium priority" #:provenance 'MEMORY)))
      (session-submit! session low #:priority 10 #:relevance 1 #:origin 'GENERATIVE)
      (session-submit! session high #:priority 50 #:relevance 1 #:origin 'PLANNER)
      (session-submit! session medium #:priority 20 #:relevance 1 #:origin 'MEMORY)
      (let* ((winner (session-run-workspace-round! session))
             (events (state-events (session-state session)))
             (started (find (lambda (event) (eq? (event-type event) 'WorkspaceRoundStarted)) events))
             (completed (find (lambda (event) (eq? (event-type event) 'WorkspaceRoundCompleted)) events)))
        (and (equal? (co-id winner) (co-id high))
             (= (assoc-ref (event-payload started) 'candidate-count) 3)
             (equal? (assoc-ref (event-payload completed) 'winner) (co-id high))
             (null? (workspace-active (session-workspace session)))
             (= (length (workspace-candidates (session-workspace session))) 2)))))

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

  (test-assert "terminal cleanup removes active and pending proposals without deleting records"
    (let* ((session (make-cognitive-session #:workspace-capacity 1))
           (goal (make-cognitive-object 'goal "Complete a bounded process" #:provenance 'USER))
           (pending (make-cognitive-object 'question "Pending old work" #:provenance 'USER)))
      (session-submit! session goal #:priority 100 #:origin 'USER)
      (session-submit! session pending #:priority 10 #:origin 'USER)
      (session-advance! session)
      (session-clear-workspace! session)
      (and (null? (workspace-active (session-workspace session)))
           (null? (workspace-candidates (session-workspace session)))
           (state-has-object? (session-state session) (co-id goal))
           (state-has-object? (session-state session) (co-id pending))))))

  (test-assert "processor failures become durable semantic events"
    (let* ((session (make-cognitive-session))
           (broken (make-cognitive-processor
                    'BROKEN '(GoalCreated)
                    (lambda (event) (error "processor exploded"))))
           (goal (make-cognitive-object 'goal "Observe processor failure" #:provenance 'USER)))
      (attach-processor! session broken)
      (session-emit! session 'GoalCreated goal #:origin 'CONTROL)
      (let ((failure (find (lambda (event) (eq? (event-type event) 'ProcessorFailed))
                           (state-events (session-state session)))))
        (and failure
             (eq? (assoc-ref (event-payload failure) 'processor) 'BROKEN)
             (string-contains (assoc-ref (event-payload failure) 'details)
                              "processor exploded")))))

  (test-assert "trace sink observes every semantic event with current workspace state"
    (let ((traces '()))
      (let* ((session
              (make-cognitive-session
               #:trace-sink
               (lambda (observed-session event)
                 (set! traces
                       (cons (list (event-type event)
                                   (length (workspace-candidates
                                            (session-workspace observed-session))))
                             traces)))))
             (goal (make-cognitive-object 'goal "Trace this goal" #:provenance 'USER)))
        (session-submit! session goal #:priority 100 #:origin 'USER)
        (session-run-workspace-round! session)
        (let ((ordered (reverse traces)))
          (and (equal? (caar ordered) 'CandidateSubmitted)
               (= (cadar ordered) 1)
               (member 'WorkspaceRoundStarted (map car ordered))
               (member 'WorkspaceBroadcast (map car ordered))
               (member 'WorkspaceRoundCompleted (map car ordered)))))))

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
             (let* ((records (filter (lambda (co) (eq? (co-type co) 'observation)) objects))
                    (record (and (pair? records) (co-content (car records)))))
               (and (= (length records) 1)
                    (assoc-ref record 'environment-hash)
                    (assoc-ref record 'output-hash)
                    (assoc-ref record 'dependencies)))))))

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
