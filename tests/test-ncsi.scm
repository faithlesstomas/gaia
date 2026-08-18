;;; Test suite for NCSI protocol (gcas.ncsi.v1) and J-space Processor (M0 Milestone)

(use-modules (srfi srfi-1)
             (srfi srfi-9)
             (gaia com)
             (gaia cognitive-bus)
             (gaia cognitive-session)
             (gaia cognitive-state)
             (gaia cognitive-processor)
             (gaia workspace)
             (gaia ncsi)
             (gaia jspace-processor)
             (gaia ncsi-adapter))

(define (assert-true msg val)
  (unless val
    (error (format #f "Assertion FAILED: ~a (expected true, got ~s)" msg val))))

(define (assert-equal msg expected actual)
  (unless (equal? expected actual)
    (error (format #f "Assertion FAILED: ~a (expected ~s, got ~s)" msg expected actual))))

(define (assert-throws msg thunk)
  (let ((threw #f))
    (catch #t
      (lambda () (thunk))
      (lambda _ (set! threw #t)))
    (unless threw
      (error (format #f "Assertion FAILED: ~a (expected exception but none was raised)" msg)))))

(define (run-tests)
  (format #t "\n========================================\n")
  (format #t "Running NCSI & J-space Processor Test Suite\n")
  (format #t "========================================\n\n")

  ;; ---------------------------------------------------------------------------
  ;; 1. Concept creation & serialization
  ;; ---------------------------------------------------------------------------
  (format #t "[1/7] Testing <ncsi-concept> records and serialization... ")
  (let* ((c1 (make-ncsi-concept 42 "lambda" 0.95))
         (alist1 (concept->alist c1))
         (c2 (alist->concept alist1)))
    (assert-equal "concept token-id" 42 (concept-token-id c2))
    (assert-equal "concept display-text" "lambda" (concept-display-text c2))
    (assert-equal "concept score" 0.95 (concept-score c2))
    (assert-throws "invalid score type" (lambda () (make-ncsi-concept 1 "foo" "bad-score")))
    (assert-throws "missing fields in alist" (lambda () (alist->concept '((token-id . 1))))))
  (format #t "PASS\n")

  ;; ---------------------------------------------------------------------------
  ;; 2. Neural Observation creation & serialization
  ;; ---------------------------------------------------------------------------
  (format #t "[2/7] Testing <ncsi-neural-observation> serialization... ")
  (let* ((c1 (make-ncsi-concept 101 "define" 0.88))
         (c2 (make-ncsi-concept 102 "syntax-case" 0.72))
         (obs (make-ncsi-neural-observation
               #:request-id "req-001"
               #:forward-pass-id "fp-001"
               #:model-id "gemma4-e2b"
               #:model-revision "rev-1"
               #:tokenizer-revision "tok-1"
               #:lens-id "jlens-l12"
               #:lens-revision "lens-v1"
               #:layer 12
               #:position 15
               #:concepts (list c1 c2)
               #:readout-method "jlens-sparse"
               #:reconstruction-error 0.05))
         (obs-alist (observation->alist obs))
         (obs-restored (alist->observation obs-alist)))
    (assert-equal "obs request-id" "req-001" (obs-request-id obs-restored))
    (assert-equal "obs layer" 12 (obs-layer obs-restored))
    (assert-equal "obs position" 15 (obs-position obs-restored))
    (assert-equal "obs concepts count" 2 (length (obs-concepts obs-restored)))
    (assert-equal "obs reconstruction error" 0.05 (obs-reconstruction-error obs-restored)))
  (format #t "PASS\n")

  ;; ---------------------------------------------------------------------------
  ;; 3. Protocol validation & Incompatible version rejection
  ;; ---------------------------------------------------------------------------
  (format #t "[3/7] Testing NCSI protocol validation and version rejection... ")
  (assert-throws "incompatible schema version"
                 (lambda ()
                   (make-ncsi-neural-observation
                    #:schema-version "gcas.ncsi.v999"
                    #:request-id "req-1" #:forward-pass-id "fp-1"
                    #:model-id "m" #:model-revision "r" #:tokenizer-revision "t"
                    #:lens-id "l" #:lens-revision "r" #:layer 1 #:position 1)))
  (assert-throws "empty request-id"
                 (lambda ()
                   (make-ncsi-neural-observation
                    #:request-id "" #:forward-pass-id "fp-1"
                    #:model-id "m" #:model-revision "r" #:tokenizer-revision "t"
                    #:lens-id "l" #:lens-revision "r" #:layer 1 #:position 1)))
  (assert-throws "invalid layer"
                 (lambda ()
                   (make-ncsi-neural-observation
                    #:request-id "req" #:forward-pass-id "fp-1"
                    #:model-id "m" #:model-revision "r" #:tokenizer-revision "t"
                    #:lens-id "l" #:lens-revision "r" #:layer "not-an-int" #:position 1)))
  (format #t "PASS\n")

  ;; ---------------------------------------------------------------------------
  ;; 4. Epistemic Invariants: Neural signals cannot directly become ACCEPTED or VERIFIED
  ;; ---------------------------------------------------------------------------
  (format #t "[4/7] Testing GCAS Epistemic Invariants for NEURAL_J_LENS... ")
  (assert-throws "NEURAL_J_LENS cannot initially be ACCEPTED"
                 (lambda ()
                   (make-cognitive-object
                    'observation "neural data"
                    #:provenance 'NEURAL_J_LENS
                    #:epistemic-status 'ACCEPTED
                    #:verification-status 'UNVERIFIED)))
  (assert-throws "NEURAL_J_LENS cannot initially be VERIFIED"
                 (lambda ()
                   (make-cognitive-object
                    'observation "neural data"
                    #:provenance 'NEURAL_J_LENS
                    #:epistemic-status 'UNKNOWN
                    #:verification-status 'VERIFIED)))

  (let* ((c (make-ncsi-concept 1 "fib" 0.99))
         (obs (make-ncsi-neural-observation
               #:request-id "req-fib" #:forward-pass-id "fp-fib"
               #:model-id "gemma" #:model-revision "v1" #:tokenizer-revision "t1"
               #:lens-id "jlens" #:lens-revision "v1" #:layer 8 #:position 4
               #:concepts (list c) #:reconstruction-error 0.01))
         (co (observation->cognitive-object obs)))
    (assert-equal "co type" 'observation (co-type co))
    (assert-equal "co provenance" 'NEURAL_J_LENS (co-provenance co))
    (assert-equal "co epistemic-status" 'UNKNOWN (co-epistemic-status co))
    (assert-equal "co verification-status" 'UNVERIFIED (co-verification-status co))
    (assert-true "fact? must be false for neural observations" (not (fact? co))))
  (format #t "PASS\n")

  ;; ---------------------------------------------------------------------------
  ;; 5. J-space Processor & Proposal Generation
  ;; ---------------------------------------------------------------------------
  (format #t "[5/7] Testing J-space Processor proposal generation... ")
  (let* ((c (make-ncsi-concept 123 "recursion" 0.92))
         (obs (make-ncsi-neural-observation
               #:request-id "req-rec" #:forward-pass-id "fp-rec"
               #:model-id "m" #:model-revision "r" #:tokenizer-revision "t"
               #:lens-id "l" #:lens-revision "r" #:layer 10 #:position 8
               #:concepts (list c) #:reconstruction-error 0.05))
         (prop (jspace-observation->proposal obs #:base-priority 7)))
    (assert-true "is processor-proposal?" (processor-proposal? prop))
    (assert-equal "proposal priority" 7 (proposal-priority prop))
    (assert-equal "proposal relevance" 0.92 (proposal-relevance prop))
    (assert-equal "proposal uncertainty" 0.05 (proposal-uncertainty prop))
    (assert-equal "proposal risk is zero" 0.0 (proposal-risk prop)))
  (format #t "PASS\n")

  ;; ---------------------------------------------------------------------------
  ;; 6. End-to-end Session, Bus & Global Workspace Integration
  ;; ---------------------------------------------------------------------------
  (format #t "[6/7] Testing Session, Bus & Workspace admission of J-space observations... ")
  (let* ((session (make-cognitive-session))
         (proc (make-jspace-processor #:base-priority 8))
         (adapter (make-ncsi-client-adapter session))
         (c1 (make-ncsi-concept 200 "filter-map" 0.85))
         (obs (make-ncsi-neural-observation
               #:request-id "req-ws" #:forward-pass-id "fp-ws"
               #:model-id "gemma4" #:model-revision "r1" #:tokenizer-revision "t1"
               #:lens-id "jlens" #:lens-revision "v1" #:layer 6 #:position 10
               #:concepts (list c1) #:reconstruction-error 0.02)))

    ;; Attach J-space processor to session
    (attach-processor! session proc)

    ;; Dispatch NCSI NeuralStateObserved event via adapter
    (ncsi-dispatch-event! adapter (make-ncsi-neural-state-observed obs))

    ;; Verify proposal entered workspace candidates
    (let ((candidates (workspace-candidates (session-workspace session))))
      (assert-equal "workspace candidates count" 1 (length candidates))
      (let ((cand-co (car candidates)))
        (assert-equal "cand-co provenance" 'NEURAL_J_LENS (co-provenance cand-co))
        (assert-equal "cand-co type" 'observation (co-type cand-co))))

    ;; Admit next candidate to active focus in Workspace
    (let ((admitted (workspace-admit-next! (session-workspace session))))
      (assert-true "admitted CO exists" (cognitive-object? admitted))
      (assert-equal "admitted CO provenance" 'NEURAL_J_LENS (co-provenance admitted))
      (assert-equal "active workspace count" 1 (length (workspace-active (session-workspace session))))))
  (format #t "PASS\n")

  ;; ---------------------------------------------------------------------------
  ;; 7. Fault Tolerance & Error Isolation
  ;; ---------------------------------------------------------------------------
  (format #t "[7/7] Testing Fault Tolerance and Sidecar Error Isolation... ")
  (let* ((session (make-cognitive-session))
         (error-reported #f)
         (adapter (make-ncsi-client-adapter
                   session
                   #:on-error (lambda (err) (set! error-reported #t)))))

    ;; Dispatch malformed wire event
    (ncsi-dispatch-event! adapter '((schema-version . "gcas.ncsi.v1")
                                    (event-type . UNKNOWN_TYPE)
                                    (request-id . "bad-req")))
    (assert-true "error callback was invoked" error-reported)

    ;; Verify ProcessorFailed event recorded in session events
    (let ((events (state-events (session-state session))))
      (assert-true "ProcessorFailed event exists"
                   (any (lambda (evt) (eq? (event-type evt) 'ProcessorFailed))
                        events))))
  (format #t "PASS\n")

  (format #t "\n========================================\n")
  (format #t "ALL NCSI & J-SPACE TESTS PASSED SUCCESSFULLY!\n")
  (format #t "========================================\n\n"))

(run-tests)
