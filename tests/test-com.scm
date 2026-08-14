(define-module (tests test-com)
  #:use-module (srfi srfi-64)
  #:use-module (gaia com))

(test-begin "gaia-com")

(test-group "cognitive-object-creation"
  (test-assert "make-cognitive-object creates valid record"
    (let ((co (make-cognitive-object 'claim "Test payload")))
      (and (cognitive-object? co)
           (eq? (co-type co) 'claim)
           (string=? (co-content co) "Test payload")
           (eq? (co-provenance co) 'LLM)
           (eq? (co-epistemic-status co) 'HYPOTHESIS)
           (eq? (co-verification-status co) 'UNVERIFIED))))

  (test-assert "epistemic classification rule: LLM provenance defaults to HYPOTHESIS"
    (let ((co (make-cognitive-object 'hypothesis "Candidate answer" #:provenance 'LLM)))
      (and (hypothesis? co)
           (not (fact? co)))))

  (test-assert "execution result is observed output, not automatically a fact"
    (let ((co (make-cognitive-object 'result "(+ 1 1) -> 2" #:provenance 'REPL)))
      (and (not (fact? co))
           (eq? (co-epistemic-status co) 'UNKNOWN)
           (eq? (co-verification-status co) 'UNVERIFIED)))))

(test-group "cognitive-object-updates"
  (test-assert "co-update-epistemic creates updated copy"
    (let* ((orig (make-cognitive-object 'claim "Hypothesis text" #:provenance 'LLM))
           (updated (co-update-epistemic orig 'ACCEPTED 'VERIFIED 0.95)))
      (and (hypothesis? orig)
           (fact? updated)
           (= (co-confidence updated) 0.95)
           (string=? (co-id orig) (co-id updated)))))

  (test-assert "co-add-relation adds relational links"
    (let* ((co1 (make-cognitive-object 'goal "Goal 1"))
           (co2 (make-cognitive-object 'action "Action 1"))
           (linked (co-add-relation co2 'subgoal-of (co-id co1))))
      (equal? (co-relations linked) `((subgoal-of . ,(co-id co1))))))

  (test-assert "LLM cannot create accepted knowledge directly"
    (catch #t
      (lambda ()
        (make-cognitive-object 'claim "Unsupported assertion"
                               #:provenance 'LLM
                               #:epistemic-status 'ACCEPTED
                               #:verification-status 'VERIFIED)
        #f)
      (lambda _ #t))))

(test-group "cognitive-object-serialization"
  (test-assert "co->alist and alist->co roundtrip"
    (let* ((orig (make-cognitive-object 'claim "Claim text" #:provenance 'USER #:epistemic-status 'BELIEF))
           (alist (co->alist orig))
           (restored (alist->co alist)))
      (and (string=? (co-id orig) (co-id restored))
           (eq? (co-type orig) (co-type restored))
           (string=? (co-content orig) (co-content restored))
           (eq? (co-provenance orig) (co-provenance restored))
           (eq? (co-epistemic-status orig) (co-epistemic-status restored)))))

  (test-assert "alist->co rejects persisted metadata outside COM invariants"
    (catch #t
      (lambda ()
        (alist->co
         '(("id" . "bad-co") ("type" . "claim") ("content" . "malformed")
           ("provenance" . "LLM") ("epistemic-status" . "HYPOTHESIS")
           ("verification-status" . "UNVERIFIED") ("confidence" . 2.0)
           ("valid-from" . 0) ("valid-to" . "INF")
           ("invalidated-by" . "null") ("relations" . ())))
        #f)
      (lambda _ #t))))

(test-end "gaia-com")
