(define-module (tests test-deliberative-processor)
  #:use-module (srfi srfi-64)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-11)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia cognitive-state)
  #:use-module (gaia deliberative-processor))

(define (event-types session)
  (map event-type (state-events (session-state session))))

(define (prepared-session output)
  (let* ((session (make-cognitive-session #:workspace-capacity 7))
         (action (make-cognitive-object 'action "(+ 20 22)" #:provenance 'LLM))
         (result (make-cognitive-object 'result output #:provenance 'REPL
                                        #:relations `((produced-by . ,(co-id action))))))
    (session-submit! session action #:priority 90 #:origin 'CONTROL)
    (session-advance! session)
    (session-record-result! session (co-id action) result)
    (values session action result)))

(test-begin "gaia-deliberative-processor")

(test-assert "verified observation creates evidence and an accepted claim"
  (let-values (((session action result) (prepared-session "42")))
    (let ((outcome (deliberate-execution! session action result
                                          (lambda (_action observed) (string=? (co-content observed) "42"))
                                          #:claim-content "(+ 20 22) evaluates to 42.")))
      (and (fact? outcome)
           (member 'EvidenceFound (event-types session))
           (member 'BeliefUpdated (event-types session))))))

(test-assert "failed verification creates conflict and never an accepted claim"
  (let-values (((session action result) (prepared-session "41")))
    (let ((outcome (deliberate-execution! session action result
                                          (lambda (_action observed) (string=? (co-content observed) "42")))))
      (and (eq? (co-type outcome) 'conflict)
           (not (fact? outcome))
           (member 'EvidenceFound (event-types session))
           (member 'ConflictDetected (event-types session))))))

(test-end "gaia-deliberative-processor")
