(define-module (tests test-cognitive-session)
  #:use-module (srfi srfi-64)
  #:use-module (srfi srfi-1)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia cognitive-state)
  #:use-module (gaia workspace))

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

(test-end "gaia-cognitive-session")
