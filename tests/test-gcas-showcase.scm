(define-module (tests test-gcas-showcase)
  #:use-module (srfi srfi-64)
  #:use-module (srfi srfi-1)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia gcas-showcase))

(define (event-types result)
  (map event-type (assoc-ref result 'events)))

(test-begin "gaia-gcas-showcase")

(test-group "confirmed-reference-cycle"
  (let* ((result (run-gcas-reference-cycle))
         (claim (assoc-ref result 'claim))
         (events (event-types result)))
    (test-equal "showcase confirms the deterministic runtime claim"
      'CONFIRMED
      (assoc-ref result 'outcome))
    (test-assert "accepted claim is a verified fact with evidence provenance"
      (and (fact? claim)
           (member 'BeliefUpdated events)
           (member 'EvidenceFound events)
           (member 'GoalCompleted events)))
    (test-assert "showcase traverses all required reference-cycle event phases"
      (every (lambda (event-type)
               (member event-type events))
             '(ObservationReceived GoalCreated MemoryRetrieved HypothesisProposed
               CandidateSubmitted WorkspaceBroadcast ActionRequested ActionCompleted
               EvidenceFound BeliefUpdated ReflectionRaised GoalCompleted)))))

(test-group "conflicting-evidence-cycle"
  (let* ((result (run-gcas-reference-cycle
                  #:executor (lambda (_action)
                               '((status . ok) (output . "41")))))
         (events (event-types result)))
    (test-equal "conflicting evidence is an explicit terminal outcome"
      'CONFLICTING_EVIDENCE
      (assoc-ref result 'outcome))
    (test-assert "conflict does not create an accepted claim"
      (and (not (assoc-ref result 'claim))
           (member 'ConflictDetected events)
           (member 'ProcessTerminated events)
           (not (member 'GoalCompleted events))))))

(test-group "failed-execution-cycle"
  (let* ((result (run-gcas-reference-cycle
                  #:executor (lambda (_action)
                               '((status . failed) (output . "Runtime unavailable")))))
         (events (event-types result)))
    (test-equal "execution failure is a first-class terminal outcome"
      'FAILED
      (assoc-ref result 'outcome))
    (test-assert "failed execution leaves the hypothesis unaccepted"
      (and (not (assoc-ref result 'claim))
           (member 'ActionFailed events)
           (member 'ReflectionRaised events)
           (member 'ProcessTerminated events)))))

(test-end "gaia-gcas-showcase")
