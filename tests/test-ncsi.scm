;;; Test suite for NCSI protocol (gcas.ncsi.v1) and J-space Processor (M0 Milestone)

(use-modules (srfi srfi-1)
             (srfi srfi-9)
             (json)
             (ice-9 ftw)
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

(define (fixture-data filename)
  (call-with-input-file
      (string-append (dirname (current-filename)) "/fixtures/ncsi/" filename)
    json->scm))

(define (run-tests)
  (format #t "\n========================================\n")
  (format #t "Running NCSI & J-space Processor Test Suite\n")
  (format #t "========================================\n\n")

  ;; ---------------------------------------------------------------------------
  ;; 1. Concept creation & serialization
  ;; ---------------------------------------------------------------------------
  (format #t "[1/10] Testing <ncsi-concept> records and serialization... ")
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
  (format #t "[2/10] Testing <ncsi-neural-observation> serialization... ")
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
  (format #t "[3/10] Testing NCSI protocol validation and version rejection... ")
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
  (format #t "[4/10] Testing GCAS Epistemic Invariants for NEURAL_J_LENS... ")
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
  (assert-throws "NEURAL_J_LENS cannot be promoted through co-update-epistemic"
                 (lambda ()
                   (co-update-epistemic
                    (make-cognitive-object 'claim "neural proposal"
                                           #:provenance 'NEURAL_J_LENS)
                    'ACCEPTED 'VERIFIED)))
  (assert-throws "persisted neural fact is rejected on restore"
                 (lambda ()
                   (alist->co
                    '(("id" . "co-neural")
                      ("type" . "claim")
                      ("content" . "neural data")
                      ("provenance" . "NEURAL_J_LENS")
                      ("epistemic-status" . "ACCEPTED")
                      ("verification-status" . "VERIFIED")
                      ("confidence" . 1.0)
                      ("valid-from" . 0)
                      ("valid-to" . "INF")))))

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
  (format #t "[5/10] Testing J-space Processor proposal generation... ")
  (let* ((c (make-ncsi-concept 123 "recursion" 0.92))
         (obs (make-ncsi-neural-observation
               #:request-id "req-rec" #:forward-pass-id "fp-rec"
               #:model-id "m" #:model-revision "r" #:tokenizer-revision "t"
               #:lens-id "l" #:lens-revision "r" #:layer 10 #:position 8
               #:concepts (list c)
               #:parameters '((reconstruction-error-calibrated . #t))
               #:reconstruction-error 0.05))
         (prop (jspace-observation->proposal obs #:base-priority 7)))
    (assert-true "is processor-proposal?" (processor-proposal? prop))
    (assert-equal "proposal priority" 7 (proposal-priority prop))
    (assert-equal "proposal relevance" 0.92 (proposal-relevance prop))
    (assert-equal "proposal uncertainty" 0.05 (proposal-uncertainty prop))
    (assert-equal "proposal risk is zero" 0.0 (proposal-risk prop)))
  (format #t "PASS\n")

  (format #t "[5b] Testing uncalibrated uncertainty and proposal bounds... ")
  (let* ((session (make-cognitive-session))
         (proc (make-jspace-processor #:max-proposals 1))
         (adapter (make-ncsi-client-adapter session))
         (obs (make-ncsi-neural-observation
               #:request-id "req-bounded" #:forward-pass-id "fp-bounded"
               #:model-id "m" #:model-revision "r" #:tokenizer-revision "t"
               #:lens-id "l" #:lens-revision "r" #:layer 1 #:position 1
               #:concepts (list (make-ncsi-concept 1 "x" 0.7)))))
    (assert-equal "uncalibrated readout is maximally uncertain" 1.0
                  (proposal-uncertainty (jspace-observation->proposal obs)))
    (attach-processor! session proc)
    (ncsi-dispatch-event! adapter (make-ncsi-generation-started "req-bounded" "m"))
    (ncsi-dispatch-event! adapter (make-ncsi-neural-state-observed obs))
    ;; A duplicate layer/forward-pass is suppressed and the per-request bound
    ;; prevents an unbounded Workspace candidate queue.
    (ncsi-dispatch-event! adapter (make-ncsi-neural-state-observed obs))
    (assert-equal "one bounded proposal" 1
                  (length (workspace-candidates (session-workspace session)))))
  (format #t "PASS\n")

  ;; ---------------------------------------------------------------------------
  ;; 6. End-to-end Session, Bus & Global Workspace Integration
  ;; ---------------------------------------------------------------------------
  (format #t "[6/10] Testing Session, Bus & Workspace admission of J-space observations... ")
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

    ;; An observation belongs to an explicitly started request.
    (ncsi-dispatch-event! adapter (make-ncsi-generation-started "req-ws" "gemma4"))

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
  ;; 8. Complete wire validation and transport-independent JSON fixtures
  ;; ---------------------------------------------------------------------------
  (format #t "[7/10] Testing NCSI wire fixtures and bounded validation... ")
  (let ((valid-events (vector->list (fixture-data "gcas.ncsi.v1.valid.json")))
        (invalid-cases (vector->list (fixture-data "gcas.ncsi.v1.invalid.json"))))
    ;; Fixtures use JSON strings and arrays; the parser must accept them without
    ;; a Scheme-specific conversion layer.
    (for-each (lambda (event) (assert-true "valid JSON fixture parses" (ncsi-event? (parse-ncsi-event event))))
              valid-events)
    (for-each (lambda (case)
                (assert-throws "invalid JSON fixture is rejected"
                               (lambda () (parse-ncsi-event (cdr (assoc "event" case))))))
              invalid-cases)
    (assert-throws "negative layer is rejected"
                   (lambda ()
                     (make-ncsi-neural-observation
                      #:request-id "r" #:forward-pass-id "fp" #:model-id "m"
                      #:model-revision "v" #:tokenizer-revision "t"
                      #:lens-id "l" #:lens-revision "v" #:layer -1 #:position 0)))
    (assert-throws "out-of-range concept score is rejected"
                   (lambda () (make-ncsi-concept 1 "x" 1.01)))
    (assert-throws "malformed token span is rejected"
                   (lambda ()
                     (make-ncsi-neural-observation
                      #:request-id "r" #:forward-pass-id "fp" #:model-id "m"
                      #:model-revision "v" #:tokenizer-revision "t"
                      #:lens-id "l" #:lens-revision "v" #:layer 0 #:position '(4 2)))))
  (format #t "PASS\n")

  ;; ---------------------------------------------------------------------------
  ;; 9. Request lifecycle, durable event trace, and exactly-once terminal state
  ;; ---------------------------------------------------------------------------
  (format #t "[8/10] Testing NCSI lifecycle and durable audit trace... ")
  (let* ((state-path "/tmp/gaia-ncsi-lifecycle-state.scm")
         (_ (when (file-exists? state-path) (delete-file state-path)))
         (session (make-cognitive-session #:state-path state-path #:restore? #f))
         (adapter (make-ncsi-client-adapter session))
         (events (vector->list (fixture-data "gcas.ncsi.v1.valid.json"))))
    (assert-true "delta before start is rejected"
                 (not (ncsi-dispatch-event! adapter (cadr events))))
    (for-each (lambda (event)
                (assert-true "valid lifecycle event accepted"
                             (ncsi-dispatch-event! adapter event)))
              events)
    (let ((types (map event-type (state-events (session-state session)))))
      (assert-true "started is durable" (memq 'GenerationStarted types))
      (assert-true "delta is durable" (memq 'TokenDelta types))
      (assert-true "observation is durable" (memq 'NeuralStateObserved types))
      (assert-true "completion is durable" (memq 'GenerationCompleted types)))
    (let ((restored-types
           (map event-type (state-events (load-cognitive-state state-path)))))
      (assert-true "completion survives session reload"
                   (memq 'GenerationCompleted restored-types)))
    (assert-true "duplicate terminal event is rejected"
                 (not (ncsi-dispatch-event! adapter (last events))))
    (let ((types (map event-type (state-events (session-state session)))) )
      (assert-equal "one durable completion" 1
                    (length (filter (lambda (type) (eq? type 'GenerationCompleted)) types)))
      (assert-true "typed adapter failure is durable" (memq 'NCSI_AdapterFailed types))
      (assert-true "fallback need is observable" (memq 'NCSI_FallbackRequired types)))
    (delete-file state-path))
  (format #t "PASS\n")

  ;; ---------------------------------------------------------------------------
  ;; 10. Typed terminal failure is the cancellation/timeout outcome carrier
  ;; ---------------------------------------------------------------------------
  (format #t "[9/10] Testing typed terminal failures... ")
  (let* ((session (make-cognitive-session))
         (adapter (make-ncsi-client-adapter session)))
    (assert-true "start accepts request"
                 (ncsi-dispatch-event! adapter
                                       (make-ncsi-generation-started "timeout-request" "m")))
    (assert-true "timeout failure terminates request"
                 (ncsi-dispatch-event! adapter
                                       (make-ncsi-generation-failed
                                        "timeout-request" "TIMEOUT" "sidecar timeout")))
    (assert-true "post-terminal token is rejected"
                 (not (ncsi-dispatch-event! adapter
                                            (make-ncsi-token-delta "timeout-request" 1 "late")))))
  (format #t "PASS\n")

  ;; ---------------------------------------------------------------------------
  ;; 7. Fault Tolerance & Error Isolation
  ;; ---------------------------------------------------------------------------
  (format #t "[10/10] Testing Fault Tolerance and Sidecar Error Isolation... ")
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
