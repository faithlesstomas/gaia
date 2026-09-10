(define-module (gaia uncertainty)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-state)
  #:export (VALID-UNCERTAINTY-SOURCES
            make-calculus-declaration
            make-uncertainty-assessment
            make-correctness-observation
            make-calibration-record
            calibration-scope-status
            uncertainty-assessment-valid?
            rebuild-uncertainty-projection
            uncertainty-projection-assessments
            uncertainty-projection-current
            uncertainty-invalidate!
            uncertainty-supersede!
            uncertainty-calculi-compatible?
            beta-mean
            beta-cdf
            beta-binomial-cdf
            beta-bernoulli-prior
            beta-bernoulli-update
            calibration-summary
            uncertainty-conformance-report
            uncertainty-decision))

(define VALID-UNCERTAINTY-SOURCES
  '(ALEATORIC PARAMETRIC_EPISTEMIC STRUCTURAL_EPISTEMIC
               DISTRIBUTIONAL COMPUTATIONAL OUTCOME_DECISION))

(define (nonempty-string? value)
  (and (string? value) (> (string-length value) 0)))

(define (probability? value)
  (and (number? value) (<= 0 value 1)))

(define (proper-alist? value)
  (and (list? value) (every pair? value)))

(define (require condition message . irritants)
  (unless condition (apply error message irritants)))

(define* (make-calculus-declaration id version
                                    #:key value-domain interpretation operations
                                    assumptions diagnostics compatible-quantities
                                    unsupported-operations
                                    (producer 'SYMBOLIC_INFERENCE))
  (require (and (symbol? id) (nonempty-string? version)
                (not (eq? value-domain #f)) (nonempty-string? interpretation)
                (list? operations) (list? assumptions) (proper-alist? diagnostics)
                (list? compatible-quantities) (list? unsupported-operations))
           "Invalid calculus declaration" id version)
  (make-cognitive-object
   'calculus-declaration
   `((calculus-id . ,id) (calculus-version . ,version)
     (value-domain . ,value-domain) (interpretation . ,interpretation)
     (operations . ,operations) (assumptions . ,assumptions)
     (diagnostics . ,diagnostics)
     (compatible-quantities . ,compatible-quantities)
     (unsupported-operations . ,unsupported-operations))
   #:provenance producer))

(define* (make-uncertainty-assessment target-ref quantity calculus
                                      #:key value outcome-space semantics units
                                      uncertainty-sources (conditioned-on '())
                                      (assumptions '()) (lineage '()) (dependence '())
                                      method (diagnostics '())
                                      (previous-assessment-refs '())
                                      (calibration-ref 'NOT_EVALUATED)
                                      scope (producer 'SYMBOLIC_INFERENCE)
                                      (created-at (current-time))
                                      (valid-from #f) (valid-to 'INF))
  (require (and (nonempty-string? target-ref) (or (symbol? quantity) (nonempty-string? quantity))
                (cognitive-object? calculus)
                (eq? (co-type calculus) 'calculus-declaration)
                (not (eq? value #f)) (not (eq? outcome-space #f))
                (nonempty-string? semantics) (or (symbol? units) (nonempty-string? units))
                (pair? uncertainty-sources)
                (every (lambda (source) (memq source VALID-UNCERTAINTY-SOURCES))
                       uncertainty-sources)
                (list? conditioned-on) (list? assumptions) (list? lineage)
                (list? dependence) (symbol? method) (proper-alist? diagnostics)
                (list? previous-assessment-refs) (proper-alist? scope)
                (pair? scope) (symbol? producer) (number? created-at))
           "Invalid or incomplete uncertainty assessment" target-ref quantity)
  (let* ((declaration (co-content calculus))
         (calculus-id (assoc-ref declaration 'calculus-id))
         (calculus-version (assoc-ref declaration 'calculus-version))
         (relations
          (append `((quantifies . ,target-ref)
                    (uses-calculus . ,(co-id calculus)))
                  (map (lambda (ref) (cons 'conditioned-on ref)) conditioned-on)
                  (map (lambda (ref) (cons 'updates ref)) previous-assessment-refs))))
    (make-cognitive-object
     'uncertainty-assessment
     `((target-ref . ,target-ref) (quantity . ,quantity)
       (calculus-id . ,calculus-id) (calculus-version . ,calculus-version)
       (value . ,value) (outcome-space . ,outcome-space)
       (semantics . ,semantics) (units . ,units)
       (uncertainty-sources . ,uncertainty-sources)
       (conditioned-on . ,conditioned-on) (assumptions . ,assumptions)
       (lineage . ,lineage) (dependence . ,dependence)
       (method . ,method) (diagnostics . ,diagnostics)
       (previous-assessment-refs . ,previous-assessment-refs)
       (calibration-ref . ,calibration-ref) (scope . ,scope)
       (producer . ,producer) (created-at . ,created-at))
     #:provenance producer #:valid-from valid-from #:valid-to valid-to
     #:relations relations)))

(define (uncertainty-assessment-valid? assessment)
  (and (cognitive-object? assessment)
       (eq? (co-type assessment) 'uncertainty-assessment)
       (not (co-invalidated-by assessment))
       (not (assoc-ref (co-relations assessment) 'superseded-by))))

(define* (make-correctness-observation target-ref assessment-ref outcome
                                       #:key verification-method scope
                                       (observed-at (current-time))
                                       (producer 'EXECUTION))
  (require (and (nonempty-string? target-ref) (nonempty-string? assessment-ref)
                (boolean? outcome) (symbol? verification-method)
                (proper-alist? scope) (pair? scope) (number? observed-at))
           "Invalid correctness observation" target-ref assessment-ref outcome)
  (make-cognitive-object
   'correctness-observed
   `((target-ref . ,target-ref) (assessment-ref . ,assessment-ref)
     (outcome . ,outcome) (verification-method . ,verification-method)
     (scope . ,scope) (observed-at . ,observed-at))
   #:provenance producer
   #:relations `((observes-correctness-of . ,target-ref)
                 (evaluates-assessment . ,assessment-ref))))

(define (safe-log-loss probability outcome)
  (let* ((epsilon 1e-12)
         (p (min (- 1 epsilon) (max epsilon probability))))
    (- (log (if outcome p (- 1 p))))))

(define (sample-forecast sample)
  (if (and (proper-alist? sample) (assoc 'forecast sample))
      (assoc-ref sample 'forecast)
      (car sample)))

(define (sample-outcome sample)
  (if (and (proper-alist? sample) (assoc 'outcome sample))
      (assoc-ref sample 'outcome)
      (cdr sample)))

(define (sample-assessment-ref sample)
  (and (proper-alist? sample) (assoc-ref sample 'assessment-ref)))

(define (calibration-summary samples)
  (require (and (list? samples)
                (every (lambda (sample)
                         (and (pair? sample) (probability? (sample-forecast sample))
                              (boolean? (sample-outcome sample))))
                       samples))
           "Invalid calibration samples" samples)
  (let ((sample-count (length samples)))
    (if (= sample-count 0)
        '((sample-count . 0) (brier-score . NOT_AVAILABLE)
          (log-loss . NOT_AVAILABLE) (calibration-curve . ())
          (sharpness . NOT_AVAILABLE) (coverage . NOT_AVAILABLE)
          (decision-loss . NOT_AVAILABLE))
        (let* ((brier (/ (apply + (map (lambda (sample)
                                         (expt (- (sample-forecast sample)
                                                  (if (sample-outcome sample) 1 0)) 2))
                                       samples)) sample-count))
               (log-loss (/ (apply + (map (lambda (sample)
                                            (safe-log-loss (sample-forecast sample)
                                                           (sample-outcome sample)))
                                          samples)) sample-count))
               (mean-p (/ (apply + (map sample-forecast samples)) sample-count))
               (observed (/ (count sample-outcome samples) sample-count)))
          `((sample-count . ,sample-count) (brier-score . ,brier)
            (log-loss . ,log-loss)
            (calibration-curve . (((mean-forecast . ,mean-p)
                                   (observed-rate . ,observed)
                                   (count . ,sample-count))))
            (sharpness . ,(abs (- mean-p 0.5)))
            (coverage . NOT_APPLICABLE) (decision-loss . NOT_EVALUATED))))))

(define (calibration-scope-status declared-scope observed-scope)
  (require (and (proper-alist? declared-scope) (proper-alist? observed-scope))
           "Calibration scopes must be alists" declared-scope observed-scope)
  (if (every (lambda (field)
               (equal? (assoc-ref observed-scope (car field)) (cdr field)))
             declared-scope)
      'IN_DOMAIN
      'OUT_OF_DOMAIN))

(define* (make-calibration-record target quantity calculus-id scope samples
                                  #:key (shift-status 'IN_DOMAIN)
                                  (observed-scope #f)
                                  (producer 'SYMBOLIC_INFERENCE))
  (require (and (nonempty-string? target) (symbol? calculus-id)
                (proper-alist? scope) (pair? scope)
                (memq shift-status '(IN_DOMAIN OUT_OF_DOMAIN DISTRIBUTION_SHIFT)))
           "Invalid calibration record" target scope shift-status)
  (let* ((effective-shift
          (if observed-scope
              (let ((status (calibration-scope-status scope observed-scope)))
                (if (eq? status 'OUT_OF_DOMAIN) 'OUT_OF_DOMAIN shift-status))
              shift-status))
         (summary (calibration-summary samples))
         (assessment-refs (filter-map sample-assessment-ref samples)))
    (make-cognitive-object
     'calibration-record
     `((target . ,target) (quantity . ,quantity) (calculus-id . ,calculus-id)
       (scope . ,scope) (samples . ,samples)
       (sample-count . ,(assoc-ref summary 'sample-count))
       (brier-score . ,(assoc-ref summary 'brier-score))
       (log-loss . ,(assoc-ref summary 'log-loss))
       (calibration-curve . ,(assoc-ref summary 'calibration-curve))
       (sharpness . ,(assoc-ref summary 'sharpness))
       (coverage . ,(assoc-ref summary 'coverage))
       (decision-loss . ,(assoc-ref summary 'decision-loss))
       (shift-status . ,effective-shift))
     #:provenance producer
     #:relations (map (lambda (ref) (cons 'evaluates-assessment ref))
                      assessment-refs))))

(define (rebuild-uncertainty-projection state)
  (require (cognitive-state? state) "Expected Cognitive State" state)
  (let* ((objects (state-objects state))
         (assessments (filter (lambda (co) (eq? (co-type co) 'uncertainty-assessment)) objects))
         (calibrations (filter (lambda (co) (eq? (co-type co) 'calibration-record)) objects))
         (calculi (filter (lambda (co) (eq? (co-type co) 'calculus-declaration)) objects))
         (outcomes (filter (lambda (co) (eq? (co-type co) 'correctness-observed)) objects)))
    `((assessments . ,assessments)
      (current . ,(filter uncertainty-assessment-valid? assessments))
      (calibrations . ,calibrations) (calculi . ,calculi) (outcomes . ,outcomes))))

(define (uncertainty-projection-assessments projection)
  (assoc-ref projection 'assessments))

(define (uncertainty-projection-current projection)
  (assoc-ref projection 'current))

(define (uncertainty-depends-on? assessment object-id)
  (let ((content (co-content assessment)))
    (or (member object-id (assoc-ref content 'conditioned-on))
        (member object-id (assoc-ref content 'previous-assessment-refs)))))

(define (uncertainty-invalidate! state object-id invalidator-id)
  "Invalidate an assessment and all assessment versions derived from it or
conditioned on it.  Original values and links remain intact for audit."
  (require (and (cognitive-state? state) (nonempty-string? object-id)
                (nonempty-string? invalidator-id))
           "Invalid uncertainty invalidation" object-id invalidator-id)
  (let walk ((pending (list object-id)) (visited '()) (changed '()))
    (if (null? pending) (reverse changed)
        (let ((current-id (car pending)))
          (if (member current-id visited)
              (walk (cdr pending) visited changed)
              (let* ((current (state-find state current-id))
                     (dependents
                      (filter (lambda (co)
                                (and (eq? (co-type co) 'uncertainty-assessment)
                                     (uncertainty-depends-on? co current-id)))
                              (state-objects state)))
                     (updated
                      (and current
                           (eq? (co-type current) 'uncertainty-assessment)
                           (co-update-epistemic
                            current (co-epistemic-status current)
                            (co-verification-status current)
                            (co-confidence current) invalidator-id))))
                (when updated (state-store! state updated))
                (walk (append (map co-id dependents) (cdr pending))
                      (cons current-id visited)
                      (if updated (cons updated changed) changed))))))))

(define (uncertainty-supersede! state old-id successor)
  (require (and (cognitive-state? state)
                (uncertainty-assessment-valid? successor))
           "Invalid uncertainty supersession" old-id successor)
  (let ((old (state-find state old-id)))
    (require (and old (eq? (co-type old) 'uncertainty-assessment))
             "Unknown prior uncertainty assessment" old-id)
    (let ((new (co-add-relation successor 'supersedes old-id))
          (retired (co-add-relation old 'superseded-by (co-id successor))))
      (state-store! state retired)
      (state-store! state new)
      new)))

(define (uncertainty-calculi-compatible? left right)
  (and (uncertainty-assessment-valid? left)
       (uncertainty-assessment-valid? right)
       (equal? (assoc-ref (co-content left) 'calculus-id)
               (assoc-ref (co-content right) 'calculus-id))
       (equal? (assoc-ref (co-content left) 'calculus-version)
               (assoc-ref (co-content right) 'calculus-version))
       (equal? (assoc-ref (co-content left) 'quantity)
               (assoc-ref (co-content right) 'quantity))))

(define (rising value count)
  (let loop ((index 0) (product 1.0))
    (if (= index count) product
        (loop (+ index 1) (* product (+ value index))))))

(define (choose n k)
  (if (or (< k 0) (> k n)) 0
      (let loop ((i 1) (result 1))
        (if (> i (min k (- n k))) result
            (loop (+ i 1) (/ (* result (+ (- n (min k (- n k))) i)) i))))))

(define (beta-mean alpha beta)
  (require (and (number? alpha) (> alpha 0) (number? beta) (> beta 0))
           "Beta parameters must be positive" alpha beta)
  (/ alpha (+ alpha beta)))

(define (beta-cdf alpha beta x)
  "Exact finite-sum CDF for positive integer Beta parameters."
  (require (and (integer? alpha) (> alpha 0) (integer? beta) (> beta 0)
                (probability? x))
           "Invalid integer Beta CDF arguments" alpha beta x)
  (let ((n (- (+ alpha beta) 1)))
    (apply +
           (map (lambda (j)
                  (* (choose n j) (expt x j) (expt (- 1 x) (- n j))))
                (iota (+ (- n alpha) 1) alpha)))))

(define (beta-binomial-cdf alpha beta trials max-successes)
  (require (and (number? alpha) (> alpha 0) (number? beta) (> beta 0)
                (integer? trials) (>= trials 0) (integer? max-successes)
                (>= max-successes 0))
           "Invalid beta-binomial arguments" alpha beta trials max-successes)
  (apply +
         (map (lambda (k)
                (* (choose trials k)
                   (/ (* (rising alpha k) (rising beta (- trials k)))
                      (rising (+ alpha beta) trials))))
              (iota (+ (min trials max-successes) 1)))))

(define* (beta-bernoulli-prior target-ref calculus alpha beta
                               #:key quantity scope (assumptions '())
                               (diagnostics '()))
  (require (pair? assumptions)
           "Beta-Bernoulli prior requires explicit likelihood/dependence assumptions")
  (make-uncertainty-assessment
   target-ref quantity calculus
   #:value `((distribution . BETA) (alpha . ,alpha) (beta . ,beta)
             (prior-alpha . ,alpha) (prior-beta . ,beta)
             (mean . ,(beta-mean alpha beta)))
   #:outcome-space '(0 1) #:semantics "Bayesian degree of belief over a Bernoulli rate."
   #:units 'PROBABILITY #:uncertainty-sources '(PARAMETRIC_EPISTEMIC ALEATORIC)
   #:assumptions assumptions #:method 'EXACT_BETA_BERNOULLI
   #:diagnostics
   (append diagnostics
           `((inference . EXACT)
             (prior-predictive-check .
              ((trials . 20) (max-events . 4)
               (probability . ,(beta-binomial-cdf alpha beta 20 4))))))
   #:scope scope))

(define* (beta-bernoulli-update prior calculus evidence-ref successes failures
                                #:key (diagnostics '())
                                (predictive-trials 10)
                                (predictive-max-successes 1))
  (require (and (uncertainty-assessment-valid? prior)
                (cognitive-object? calculus)
                (eq? (co-type calculus) 'calculus-declaration)
                (eq? (assoc-ref (co-content prior) 'calculus-id) 'BAYESIAN_PROBABILITY)
                (integer? successes) (>= successes 0)
                (integer? failures) (>= failures 0)
                (nonempty-string? evidence-ref))
           "Invalid Beta-Bernoulli update" prior evidence-ref successes failures)
  (let* ((content (co-content prior)) (value (assoc-ref content 'value))
         (alpha (+ (assoc-ref value 'alpha) successes))
         (beta (+ (assoc-ref value 'beta) failures))
         (prior-alpha (or (assoc-ref value 'prior-alpha) (assoc-ref value 'alpha)))
         (prior-beta (or (assoc-ref value 'prior-beta) (assoc-ref value 'beta)))
         (total-events (- alpha prior-alpha))
         (total-non-events (- beta prior-beta))
         (predictive (beta-binomial-cdf alpha beta predictive-trials
                                        predictive-max-successes))
         (sensitivity-alpha (+ 1 total-events))
         (sensitivity-beta (+ 1 total-non-events)))
    (make-uncertainty-assessment
     (assoc-ref content 'target-ref) (assoc-ref content 'quantity)
     calculus
     #:value `((distribution . BETA) (alpha . ,alpha) (beta . ,beta)
               (prior-alpha . ,prior-alpha) (prior-beta . ,prior-beta)
               (mean . ,(beta-mean alpha beta))
               (predictive-probability . ,predictive))
     #:outcome-space (assoc-ref content 'outcome-space)
     #:semantics (assoc-ref content 'semantics) #:units (assoc-ref content 'units)
     #:uncertainty-sources (assoc-ref content 'uncertainty-sources)
     #:conditioned-on (append (assoc-ref content 'conditioned-on) (list evidence-ref))
     #:assumptions (assoc-ref content 'assumptions)
     #:lineage (append (assoc-ref content 'lineage) (list evidence-ref))
     #:dependence (assoc-ref content 'dependence)
     #:method 'EXACT_BETA_BERNOULLI
     #:diagnostics
     (append diagnostics
             `((likelihood . BERNOULLI)
               (inference . EXACT)
               (posterior-predictive-check .
                ((trials . ,predictive-trials)
                 (max-events . ,predictive-max-successes)
                 (probability . ,predictive) (status . RECORDED)))
               (sensitivity .
                ((alternative-prior . BETA-1-1)
                 (posterior . (,sensitivity-alpha ,sensitivity-beta))
                 (probability-rate<0.10 .
                  ,(beta-cdf sensitivity-alpha sensitivity-beta 0.10))))
               (approximate-inference . #f)))
     #:previous-assessment-refs (list (co-id prior))
     #:calibration-ref (assoc-ref content 'calibration-ref)
     #:scope (assoc-ref content 'scope))))

(define* (uncertainty-decision assessment
                               #:key accept-threshold risk reversible?
                               expected-information-gain information-cost
                               (out-of-domain? #f) (shift? #f))
  "Return a Goal-scoped inspectable decision; no universal threshold exists."
  (require (and (uncertainty-assessment-valid? assessment)
                (probability? accept-threshold) (number? risk) (>= risk 0)
                (boolean? reversible?) (number? expected-information-gain)
                (number? information-cost))
           "Invalid uncertainty decision inputs")
  (let* ((value (assoc-ref (co-content assessment) 'value))
         (probability (or (assoc-ref value 'predictive-probability)
                          (assoc-ref value 'probability)
                          (assoc-ref value 'mean))))
    (require (probability? probability) "Assessment lacks a decision probability" assessment)
    `((decision . ,(cond
                    ((or out-of-domain? shift?) (if (> risk 0.5) 'ESCALATE 'ABSTAIN))
                    ((and (>= probability accept-threshold) reversible?) 'ACCEPT)
                    ((> expected-information-gain information-cost) 'ACQUIRE_EVIDENCE)
                    ((> risk 0.5) 'ESCALATE)
                    (else 'ABSTAIN)))
      (probability . ,probability) (threshold . ,accept-threshold)
      (risk . ,risk) (reversible . ,reversible?)
      (expected-information-gain . ,expected-information-gain)
      (information-cost . ,information-cost)
      (out-of-domain . ,out-of-domain?) (distribution-shift . ,shift?))))

(define (uncertainty-conformance-report state)
  (let* ((projection (rebuild-uncertainty-projection state))
         (assessments (uncertainty-projection-assessments projection))
         (calculi (assoc-ref projection 'calculi))
         (bayesian?
          (any (lambda (co)
                 (eq? (assoc-ref (co-content co) 'calculus-id)
                      'BAYESIAN_PROBABILITY))
               assessments)))
    `((profile . GCAS-UNCERTAINTY-0.3)
      (status . ,(if (and (pair? assessments) (pair? calculi)) 'CONFORMANT 'NOT_EXERCISED))
      (assessment-count . ,(length assessments))
      (calibration-count . ,(length (assoc-ref projection 'calibrations)))
      (bayesian-profile . ((profile . GCAS-BAYESIAN-0.3)
                           (scope . BETA_BERNOULLI)
                           (status . ,(if bayesian? 'CONFORMANT 'NOT_EXERCISED)))))))
