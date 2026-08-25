(define-module (gaia ncsi-evaluation)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia ncsi)
  #:use-module (gaia rai-ncsi-adapter)
  #:use-module (gaia workspace)
  #:export (NCSI-EVALUATION-MODES
            run-ncsi-evaluation
            summarize-ncsi-evaluation
            ncsi-readiness-decision))

(define NCSI-EVALUATION-MODES '(TEXT_ONLY OBSERVATION_ONLY NCSI_POLICY))

(define (field-ref alist key)
  (let ((entry (or (assoc key alist)
                   (assoc (if (symbol? key) (symbol->string key) (string->symbol key))
                          alist))))
    (and entry (cdr entry))))

(define (task-id task) (field-ref task "id"))
(define (task-prompt task) (field-ref task "prompt"))
(define (task-expected task) (field-ref task "expected-contains"))

(define (contains-ci? text fragment)
  (and (string? text) (string? fragment)
       (and (string-contains (string-downcase text) (string-downcase fragment))
            #t)))

(define (observation-concepts observation)
  (map concept-display-text (obs-concepts observation)))

(define (elapsed-seconds started)
  (/ (- (get-internal-real-time) started)
     (* 1.0 internal-time-units-per-second)))

(define (unique strings)
  (delete-duplicates strings string=?))

(define (run-case task mode repetition client-factory model lens-id options)
  (let* ((session (make-cognitive-session))
         (client (client-factory session))
         (concepts '())
         (started (get-internal-real-time))
         (request-id (format #f "m5-~a-~a-~a"
                             (or (field-ref options 'run-id) "run")
                             (string-append
                              (string-downcase (symbol->string mode)) "-"
                              (task-id task))
                             repetition))
         (result
          (rai-ncsi-generate!
           client (task-prompt task) model
           #:mode mode
           #:request-id request-id
           #:lens-id lens-id
           #:max-new-tokens (or (field-ref options 'max-new-tokens) 64)
           #:timeout-seconds (or (field-ref options 'timeout-seconds) 120)
           #:top-k (or (field-ref options 'top-k) 8)
           #:layers (or (field-ref options 'layers) '())
           #:max-proposals (or (field-ref options 'max-proposals) 64)
           #:on-observation
           (lambda (observation)
             (set! concepts (append (observation-concepts observation) concepts)))))
         (final-text (or (field-ref result 'final-text) ""))
         (result-mode (field-ref result 'mode)))
    `(("task" . ,(task-id task))
      ("mode" . ,(symbol->string mode))
      ("repetition" . ,repetition)
      ("request-id" . ,request-id)
      ("terminal" . ,(and (memq result-mode
                                '(TEXT_ONLY OBSERVATION_ONLY NCSI_POLICY FALLBACK))
                           #t))
      ("fallback" . ,(eq? result-mode 'FALLBACK))
      ("success" . ,(contains-ci? final-text (task-expected task)))
      ("final-text" . ,final-text)
      ("token-count" . ,(or (field-ref result 'token-count) 0))
      ("observation-count" . ,(or (field-ref result 'observation-count) 0))
      ("workspace-proposals" . ,(length
                                  (workspace-candidates
                                   (session-workspace session))))
      ("concepts" . ,(list->vector (unique concepts)))
      ("latency-seconds" . ,(elapsed-seconds started)))))

(define* (run-ncsi-evaluation tasks client-factory model lens-id
                              #:key
                              (modes NCSI-EVALUATION-MODES)
                              (repeats 1)
                              (options '()))
  "Run matched M5 cases against one sidecar model and immutable lens."
  (unless (and (list? tasks) (pair? tasks) (procedure? client-factory)
               (string? model) (> (string-length model) 0)
               (string? lens-id) (> (string-length lens-id) 0)
               (integer? repeats) (> repeats 0))
    (error "Invalid NCSI evaluation configuration"))
  (append-map
   (lambda (task)
     (append-map
      (lambda (mode)
        (map (lambda (repetition)
               (run-case task mode repetition client-factory model lens-id options))
             (iota repeats 1)))
      modes))
   tasks))

(define (mean values)
  (if (null? values) 0.0 (/ (apply + values) (* 1.0 (length values)))))

(define (rate results field)
  (if (null? results)
      0.0
      (/ (count (lambda (result) (field-ref result field)) results)
         (* 1.0 (length results)))))

(define (concept-vector->list value)
  (if (vector? value) (vector->list value) value))

(define (jaccard left right)
  (let* ((left (unique left))
         (right (unique right))
         (intersection (count (lambda (item) (member item right)) left))
         (union (+ (length left) (length right) (- intersection))))
    (if (zero? union) 1.0 (/ intersection (* 1.0 union)))))

(define (pairwise-concept-stability results)
  (let loop ((remaining results) (scores '()))
    (if (null? remaining)
        (and (pair? scores) (mean scores))
        (let* ((head (car remaining))
               (same-task
                (filter (lambda (other)
                          (and (string=? (field-ref head "task")
                                         (field-ref other "task"))
                               (not (= (field-ref head "repetition")
                                       (field-ref other "repetition")))))
                        (cdr remaining)))
               (head-concepts (concept-vector->list (field-ref head "concepts"))))
          (loop (cdr remaining)
                (append
                 (map (lambda (other)
                        (jaccard head-concepts
                                 (concept-vector->list
                                  (field-ref other "concepts"))))
                      same-task)
                 scores))))))

(define (summarize-mode results mode)
  (let* ((name (symbol->string mode))
         (selected (filter (lambda (result)
                             (string=? name (field-ref result "mode")))
                           results))
         (latencies (map (lambda (result) (field-ref result "latency-seconds"))
                         selected)))
    `(("mode" . ,name)
      ("cases" . ,(length selected))
      ("terminal-rate" . ,(rate selected "terminal"))
      ("success-rate" . ,(rate selected "success"))
      ("fallback-rate" . ,(rate selected "fallback"))
      ("mean-latency-seconds" . ,(mean latencies))
      ("mean-token-count" . ,(mean (map (lambda (r) (field-ref r "token-count"))
                                         selected)))
      ("mean-observation-count" .
       ,(mean (map (lambda (r) (field-ref r "observation-count")) selected)))
      ("mean-workspace-proposals" .
       ,(mean (map (lambda (r) (field-ref r "workspace-proposals")) selected)))
      ("concept-stability" . ,(pairwise-concept-stability selected)))))

(define (matched-output-invariant? results)
  (every
   (lambda (text-result)
     (let ((observed
            (find (lambda (candidate)
                    (and (string=? (field-ref candidate "mode") "OBSERVATION_ONLY")
                         (string=? (field-ref candidate "task")
                                   (field-ref text-result "task"))
                         (= (field-ref candidate "repetition")
                            (field-ref text-result "repetition"))))
                  results)))
       (and observed
            (string=? (field-ref text-result "final-text")
                      (field-ref observed "final-text")))))
   (filter (lambda (result) (string=? (field-ref result "mode") "TEXT_ONLY"))
           results)))

(define (summary-ref summaries mode field)
  (let ((summary (find (lambda (item)
                         (string=? (field-ref item "mode") (symbol->string mode)))
                       summaries)))
    (and summary (field-ref summary field))))

(define (ncsi-readiness-decision results summaries)
  "Conservative technical gate for an opt-in read-only experimental profile."
  (let ((observation-count
         (summary-ref summaries 'OBSERVATION_ONLY "mean-observation-count")))
    (if (and (= 1.0 (summary-ref summaries 'TEXT_ONLY "terminal-rate"))
             (= 1.0 (summary-ref summaries 'OBSERVATION_ONLY "terminal-rate"))
             (= 1.0 (summary-ref summaries 'NCSI_POLICY "terminal-rate"))
             (= 0.0 (summary-ref summaries 'OBSERVATION_ONLY "fallback-rate"))
             observation-count (> observation-count 0)
             (matched-output-invariant? results))
        "SHIP_EXPERIMENTAL"
        "REVISE")))

(define (summarize-ncsi-evaluation results)
  (let ((summaries (map (lambda (mode) (summarize-mode results mode))
                        NCSI-EVALUATION-MODES)))
    `(("schema-version" . "gaia.ncsi-evaluation.v1")
      ("modes" . ,(list->vector summaries))
      ("matched-text-observation-output" . ,(matched-output-invariant? results))
      ("decision" . ,(ncsi-readiness-decision results summaries))
      ("unsupported-claims" .
       #("J-lens readouts are not epistemic truth"
         "Token readouts are not complete model thoughts"
         "Read-only evaluation does not establish causal utility")))))
