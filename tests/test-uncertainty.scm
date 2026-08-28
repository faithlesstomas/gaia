(define-module (tests test-uncertainty)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-64)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-control)
  #:use-module (gaia cognitive-process)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia cognitive-state)
  #:use-module (gaia uncertainty))

(define (close? actual expected tolerance)
  (< (abs (- actual expected)) tolerance))

(define (bayesian-calculus)
  (make-calculus-declaration
   'BAYESIAN_PROBABILITY "0.3"
   #:value-domain 'PROBABILITY_DISTRIBUTIONS
   #:interpretation "Bayesian probability over declared events and parameters."
   #:operations '(CONDITION PREDICT MARGINALIZE)
   #:assumptions '(DECLARED_LIKELIHOOD DECLARED_DEPENDENCE)
   #:diagnostics '((exact-required . #t))
   #:compatible-quantities '(FAILURE_RATE BATCH_CORRECTNESS)
   #:unsupported-operations '(UNDECLARED_CROSS_CALCULUS_FUSION)))

(define scope
  '((pipeline . "v7") (environment . "E7") (interval . "T")
    (population . CONTROLLED_TRIALS) (model-version . "beta-bernoulli-v1")))

(test-begin "gaia-uncertainty")

(test-assert "specialized uncertainty COs fail closed but legacy confidence stays legacy"
  (and
   (catch #t
     (lambda () (make-cognitive-object 'uncertainty-assessment '()) #f)
     (lambda _ #t))
   (let* ((path "/tmp/gaia-legacy-confidence-state.scm")
          (legacy (make-cognitive-object 'claim "legacy" #:confidence 0.73
                                         #:provenance 'SYMBOLIC_INFERENCE))
          (state (make-cognitive-state #:objects (list legacy))))
     (save-cognitive-state! state path)
     (let* ((restored (load-cognitive-state path))
            (co (state-find restored (co-id legacy))))
       (and (= (co-confidence co) 0.73)
            (null? (uncertainty-projection-assessments
                    (rebuild-uncertainty-projection restored))))))))

(test-assert "Beta-Bernoulli trace reproduces the GCAS worked values"
  (let* ((calculus (bayesian-calculus))
         (prior (beta-bernoulli-prior
                 "H1" calculus 1 9 #:quantity 'FAILURE_RATE #:scope scope
                 #:assumptions '(BERNOULLI INDEPENDENT STATIONARY)
                 #:diagnostics
                 `((prior-predictive-k<=4 . ,(beta-binomial-cdf 1 9 20 4)))))
         (ua1 (beta-bernoulli-update prior calculus "E1" 1 19))
         (ua2 (beta-bernoulli-update ua1 calculus "E2" 0 30))
         (v1 (assoc-ref (co-content ua1) 'value))
         (v2 (assoc-ref (co-content ua2) 'value)))
    (and (close? (beta-binomial-cdf 1 9 20 4) 0.8694 0.0001)
         (close? (beta-mean 2 28) 0.0667 0.0001)
         (close? (beta-cdf 2 28 0.10) 0.8011 0.0001)
         (close? (assoc-ref v1 'predictive-probability) 0.8441 0.0001)
         (close? (beta-mean 2 58) 0.0333 0.0001)
         (close? (beta-cdf 2 58 0.10) 0.9849 0.0001)
         (close? (assoc-ref v2 'predictive-probability) 0.9470 0.0001)
         (eq? (co-verification-status ua2) 'UNVERIFIED))))

(test-assert "U rebuilds after restart and invalidation propagates without rewriting values"
  (let* ((path "/tmp/gaia-uncertainty-state.scm")
         (calculus (bayesian-calculus))
         (e1 (make-cognitive-object 'evidence "1 failure in 20" #:provenance 'EXECUTION))
         (e2 (make-cognitive-object 'evidence "0 failures in 30" #:provenance 'EXECUTION))
         (invalidator (make-cognitive-object 'conflict "E1 scope invalid" #:provenance 'SYMBOLIC_INFERENCE))
         (prior (beta-bernoulli-prior "H1" calculus 1 9 #:quantity 'FAILURE_RATE
                                      #:scope scope #:assumptions '(BERNOULLI)))
         (ua1 (beta-bernoulli-update prior calculus (co-id e1) 1 19))
         (ua2-raw (beta-bernoulli-update ua1 calculus (co-id e2) 0 30))
         (state (make-cognitive-state #:objects (list calculus e1 e2 invalidator prior ua1)))
         (ua2 (uncertainty-supersede! state (co-id ua1) ua2-raw)))
    (save-cognitive-state! state path)
    (let* ((restored (load-cognitive-state path))
           (before (rebuild-uncertainty-projection restored))
           (changed (uncertainty-invalidate! restored (co-id e1) (co-id invalidator)))
           (after (rebuild-uncertainty-projection restored))
           (restored-ua2 (state-find restored (co-id ua2))))
      (and (= (length (uncertainty-projection-assessments before)) 3)
           (= (length (uncertainty-projection-current before)) 2)
           (= (length changed) 2)
           (= (length (uncertainty-projection-current after)) 1)
           (= (assoc-ref (assoc-ref (co-content restored-ua2) 'value) 'alpha) 2)
           (= (assoc-ref (assoc-ref (co-content restored-ua2) 'value) 'beta) 58)
           (equal? (co-invalidated-by restored-ua2) (co-id invalidator))))))

(test-assert "correctness and calibration evaluate an immutable forecast"
  (let* ((calculus (bayesian-calculus))
         (prior (beta-bernoulli-prior "H1" calculus 1 9 #:quantity 'FAILURE_RATE
                                      #:scope scope #:assumptions '(BERNOULLI)))
         (ua1 (beta-bernoulli-update prior calculus "E1" 1 19))
         (ua2 (beta-bernoulli-update ua1 calculus "E2" 0 30))
         (forecast (assoc-ref (assoc-ref (co-content ua2) 'value)
                              'predictive-probability))
         (outcome (make-correctness-observation
                   "C1" (co-id ua2) #t #:verification-method 'EXECUTION_RESULT
                   #:scope scope))
         (record (make-calibration-record
                  "C1" 'BATCH_CORRECTNESS 'BAYESIAN_PROBABILITY scope
                  (list `((assessment-ref . ,(co-id ua2))
                          (forecast . ,forecast) (outcome . #t)))))
         (content (co-content record)))
    (and (equal? (assoc-ref (co-content outcome) 'assessment-ref) (co-id ua2))
         (= (assoc-ref content 'sample-count) 1)
         (close? (assoc-ref content 'brier-score) 0.0028 0.0001)
         (equal? (assoc-ref (co-relations record) 'evaluates-assessment)
                 (co-id ua2))
         (eq? (co-verification-status ua2) 'UNVERIFIED)
         (eq? (co-verification-status outcome) 'UNVERIFIED))))

(test-assert "calibration scope violations are detected and profiles report separately"
  (let* ((calculus (bayesian-calculus))
         (prior (beta-bernoulli-prior "H1" calculus 1 9 #:quantity 'FAILURE_RATE
                                      #:scope scope #:assumptions '(BERNOULLI)))
         (state (make-cognitive-state #:objects (list calculus prior)))
         (record (make-calibration-record
                  "C1" 'BATCH_CORRECTNESS 'BAYESIAN_PROBABILITY scope '()
                  #:observed-scope
                  '((pipeline . "v7") (environment . "E8") (interval . "T")
                    (population . CONTROLLED_TRIALS)
                    (model-version . "beta-bernoulli-v1"))))
         (report (uncertainty-conformance-report state)))
    (and (eq? (assoc-ref (co-content record) 'shift-status) 'OUT_OF_DOMAIN)
         (eq? (assoc-ref report 'status) 'CONFORMANT)
         (eq? (assoc-ref (assoc-ref report 'bayesian-profile) 'status)
              'CONFORMANT))))

(test-assert "cross-calculus assessments are not numerically combinable"
  (let* ((bayes (bayesian-calculus))
         (bound (make-calculus-declaration
                 'FORMAL_BOUND "1" #:value-domain 'INTERVALS
                 #:interpretation "Certified interval." #:operations '(INTERSECT)
                 #:assumptions '(SOUND_BOUND)
                 #:diagnostics '((proof-obligation . REQUIRED))
                 #:compatible-quantities '(FAILURE_RATE)
                 #:unsupported-operations '(BAYESIAN_CONDITIONING)))
         (a (beta-bernoulli-prior "H1" bayes 1 9 #:quantity 'FAILURE_RATE
                                  #:scope scope #:assumptions '(BERNOULLI)))
         (b (make-uncertainty-assessment
             "H1" 'FAILURE_RATE bound #:value '((lower . 0) (upper . 0.1))
             #:outcome-space '(0 1) #:semantics "Formal upper bound."
             #:units 'PROBABILITY #:uncertainty-sources '(COMPUTATIONAL)
             #:assumptions '(SOUND_BOUND) #:method 'FORMAL_DERIVATION
             #:diagnostics '((valid . #t)) #:scope scope)))
    (not (uncertainty-calculi-compatible? a b))))

(test-assert "Goal-scoped decision supports evidence acquisition, acceptance, and shift response"
  (let* ((calculus (bayesian-calculus))
         (prior (beta-bernoulli-prior "H1" calculus 1 9 #:quantity 'FAILURE_RATE
                                      #:scope scope #:assumptions '(BERNOULLI)))
         (ua1 (beta-bernoulli-update prior calculus "E1" 1 19))
         (ua2 (beta-bernoulli-update ua1 calculus "E2" 0 30))
         (first (uncertainty-decision ua1 #:accept-threshold 0.94 #:risk 0.4
                                      #:reversible? #t #:expected-information-gain 0.5
                                      #:information-cost 0.1))
         (second (uncertainty-decision ua2 #:accept-threshold 0.94 #:risk 0.4
                                       #:reversible? #t #:expected-information-gain 0.1
                                       #:information-cost 0.2))
         (shifted (uncertainty-decision ua2 #:accept-threshold 0.94 #:risk 0.9
                                        #:reversible? #t #:expected-information-gain 0.1
                                        #:information-cost 0.2
                                        #:out-of-domain? #t #:shift? #t)))
    (and (eq? (assoc-ref first 'decision) 'ACQUIRE_EVIDENCE)
         (eq? (assoc-ref second 'decision) 'ACCEPT)
         (eq? (assoc-ref shifted 'decision) 'ESCALATE))))

(test-assert "Control attends to uncertain high-impact work without epistemic promotion"
  (let* ((session (make-cognitive-session #:workspace-capacity 1))
         (routine (make-cognitive-object 'observation "routine" #:provenance 'SENSOR))
         (impact (make-cognitive-object 'conflict "shift near safety boundary"
                                        #:provenance 'SYMBOLIC_INFERENCE)))
    (session-submit! session routine #:priority 50 #:relevance 1 #:origin 'SENSOR)
    (session-submit! session impact #:priority 35 #:risk 1 #:conflict 1
                     #:out-of-domain 1 #:information-gain 1 #:origin 'CONTROL)
    (let ((winner (session-advance! session)))
      (and (equal? (co-id winner) (co-id impact))
           (eq? (co-verification-status winner) 'UNVERIFIED)
           (eq? (co-epistemic-status winner) 'BELIEF)
           (= (co-confidence winner) 1.0)
           (eq? (assoc-ref (co-relations winner) 'uncertainty-treatment)
                'NO_APPLICABLE_ASSESSMENT)))))

(test-end "gaia-uncertainty")
