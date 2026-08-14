(define-module (gaia gcas-evaluation)
  #:use-module (ice-9 match)
  #:use-module (ice-9 optargs)
  #:use-module (srfi srfi-1)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-process)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia cognitive-state)
  #:use-module (gaia core)
  #:use-module (gaia goal-verifier)
  #:use-module (gaia production-processors)
  #:export (make-datum-evaluation-task
            evaluation-task-id
            evaluation-task-category
            evaluation-task-prompt
            default-live-evaluation-tasks
            select-evaluation-tasks
            run-evaluation-case
            run-evaluation-matrix
            summarize-evaluation-results
            summarize-evaluation-cells))

;; Live evaluation tasks are deliberately independent from a model provider.
;; Their acceptance boundary consumes only the executed Action and Result COs.

(define* (make-datum-evaluation-task id category prompt expected
                                     #:key
                                     (required-binding #f)
                                     (max-transitions 32)
                                     (max-stalled-transitions 8)
                                     (max-failures 3)
                                     (max-replans 3))
  (unless (and (symbol? id) (symbol? category) (string? prompt)
               (or (not required-binding) (symbol? required-binding)))
    (error "Invalid GCAS evaluation task" id category prompt))
  `((id . ,id)
    (category . ,category)
    (prompt . ,prompt)
    (expected . ,expected)
    (required-binding . ,required-binding)
    (completion-criteria . ,(format #f
                                    "The final Scheme value must equal ~s. An independent datum verifier must accept it."
                                    expected))
    (max-transitions . ,max-transitions)
    (max-stalled-transitions . ,max-stalled-transitions)
    (max-failures . ,max-failures)
    (max-replans . ,max-replans)))

(define (evaluation-task-id task) (assoc-ref task 'id))
(define (evaluation-task-category task) (assoc-ref task 'category))
(define (evaluation-task-prompt task) (assoc-ref task 'prompt))

(define default-live-evaluation-tasks
  (list
   (make-datum-evaluation-task
    'arithmetic-42 'exact-value
    "Compute (17 * 3) - 9 in Guile Scheme. Return the exact numeric result as the final expression."
    42)
   (make-datum-evaluation-task
    'map-squares 'list-transform
    "Use Guile Scheme to square each value in (1 2 3 4 5). Return exactly the resulting list as the final expression."
    '(1 4 9 16 25))
   (make-datum-evaluation-task
    'filter-evens 'list-filter
    "Use Guile Scheme to retain only the even values from (1 2 3 4 5 6 7 8 9 10). Return exactly the resulting list as the final expression."
    '(2 4 6 8 10))
   (make-datum-evaluation-task
    'factorial-6 'procedure
    "Define a recursive procedure named factorial and use it to compute factorial of 6. Return the exact numeric result as the final expression."
    720 #:required-binding 'factorial)
   (make-datum-evaluation-task
    'fibonacci-10 'procedure
    "Define a procedure named fibonacci-sequence and return exactly the first ten Fibonacci terms, starting with 0 and 1, as the final Scheme value."
    '(0 1 1 2 3 5 8 13 21 34)
    #:required-binding 'fibonacci-sequence)))

(define (select-evaluation-tasks tasks ids)
  "Return TASKS selected by symbol IDS, preserving corpus order.
An empty IDS list selects the complete corpus."
  (if (null? ids)
      tasks
      (begin
        (for-each
         (lambda (id)
           (unless (find (lambda (task) (eq? (evaluation-task-id task) id)) tasks)
             (error "Unknown GCAS evaluation task" id)))
         ids)
        (filter (lambda (task) (memq (evaluation-task-id task) ids)) tasks))))

(define (read-single-datum text)
  (catch #t
    (lambda ()
      (call-with-input-string text
        (lambda (port)
          (let ((value (read port))
                (tail (read port)))
            (and (not (eof-object? value))
                 (eof-object? tail)
                 (cons #t value))))))
    (lambda _ #f)))

(define (read-all-datums text)
  (catch #t
    (lambda ()
      (call-with-input-string text
        (lambda (port)
          (let loop ((forms '()))
            (let ((form (read port)))
              (if (eof-object? form)
                  (reverse forms)
                  (loop (cons form forms))))))))
    (lambda _ #f)))

(define (form-defines-binding? form binding)
  (match form
    (('define (name . args) . body) (eq? name binding))
    (('define name value) (eq? name binding))
    (('begin . forms) (any (lambda (nested)
                            (form-defines-binding? nested binding))
                          forms))
    (_ #f)))

(define (action-defines-binding? text binding)
  (let ((forms (read-all-datums text)))
    (and forms
         (any (lambda (form) (form-defines-binding? form binding)) forms))))

(define (task-verifier task)
  (lambda (goal action result evidence execution-claim state)
    (let* ((parsed (read-single-datum (co-content result)))
           (binding (assoc-ref task 'required-binding))
           (action-ok? (or (not binding)
                           (action-defines-binding? (co-content action) binding)))
           (result-ok? (and parsed
                            (equal? (cdr parsed) (assoc-ref task 'expected)))))
      (if (and action-ok? result-ok?)
          (make-goal-verdict
           'SATISFIED
           "The independent live-evaluation oracle accepted the executed Result."
           (format #f "Verified result: ~s" (assoc-ref task 'expected)))
          (make-goal-verdict
           'REJECTED
           (string-append
            (if action-ok? "" "The required procedure definition was not observed. ")
            (format #f "Expected final datum ~s, observed ~s."
                    (assoc-ref task 'expected)
                    (and parsed (cdr parsed)))))))))

(define (metadata-ref metadata key)
  (let ((value (and (list? metadata)
                    (or (assoc-ref metadata key)
                        (assoc-ref metadata (symbol->string key))))))
    (if (number? value) value 0)))

(define (evaluation-relation-ref co key)
  (assoc-ref (co-relations co) key))

(define* (run-evaluation-case task model repetition generate execute
                              #:key (run-id #f))
  "Run one TASK/MODEL/REPETITION through the production GCAS processor.

GENERATE receives MODEL, RUN-ID, cognitive PROMPT, SUCCESS and FAILURE.
SUCCESS accepts response text and optional metadata. EXECUTE uses the normal
production callback contract. This injection boundary keeps the matrix
provider- and runtime-agnostic."
  (let* ((case-id (or run-id
                      (format #f "eval-~a-~a-~a"
                              model (evaluation-task-id task) repetition)))
         (session (make-cognitive-session #:workspace-capacity 8 #:restore? #f))
         (model-calls 0)
         (execution-calls 0)
         (prompt-tokens 0)
         (completion-tokens 0)
         (total-tokens 0)
         (responses '())
         (actions '())
         (finish-records '())
         (adapter-errors '())
         (started (get-internal-real-time))
         (process
          (start-production-process!
           session (evaluation-task-prompt task)
           #:completion-criteria (assoc-ref task 'completion-criteria)
           #:max-transitions (assoc-ref task 'max-transitions)
           #:max-stalled-transitions (assoc-ref task 'max-stalled-transitions)
           #:max-failures (assoc-ref task 'max-failures)
           #:max-replans (assoc-ref task 'max-replans)
           #:verify-goal (task-verifier task)
           #:generate
           (lambda (context succeed fail)
             (set! model-calls (+ model-calls 1))
             (catch #t
               (lambda ()
                 (generate
                  model case-id context
                  (lambda* (response #:optional (metadata '()))
                    (set! responses (cons response responses))
                    (set! prompt-tokens
                          (+ prompt-tokens (metadata-ref metadata 'prompt_tokens)))
                    (set! completion-tokens
                          (+ completion-tokens (metadata-ref metadata 'completion_tokens)))
                    (set! total-tokens
                          (+ total-tokens (metadata-ref metadata 'total_tokens)))
                    (succeed response))
                  (lambda (message)
                    (set! adapter-errors (cons (format #f "~a" message) adapter-errors))
                    (fail (format #f "~a" message)))))
               (lambda (key . args)
                 (let ((message (format #f "~a ~s" key args)))
                   (set! adapter-errors (cons message adapter-errors))
                   (fail message)))))
           #:extract-action
           (lambda (response)
             ;; The caller supplies model text, while the production extractor
             ;; remains the same adapter used by the server.
             (extract-gcas-action response))
           #:execute
           (lambda (code succeed fail)
             (set! execution-calls (+ execution-calls 1))
             (set! actions (cons code actions))
             (catch #t
               (lambda () (execute code succeed fail))
               (lambda (key . args)
                 (let ((message (format #f "~a ~s" key args)))
                   (set! adapter-errors (cons message adapter-errors))
                   (fail 'runtime message)))))
           #:on-finished
           (lambda (outcome final-text hypothesis-text)
             (set! finish-records
                   (cons (list outcome final-text hypothesis-text)
                         finish-records))))))
    (let* ((events (state-events (session-state session)))
           (terminals
            (filter (lambda (event)
                      (memq (event-type event) '(GoalCompleted ProcessTerminated)))
                    events))
           (action-failures
            (count (lambda (event) (eq? (event-type event) 'ActionFailed)) events))
           (plans
            (count (lambda (event) (eq? (event-type event) 'PlanProposed)) events))
           (conflicts
            (filter (lambda (event) (eq? (event-type event) 'ConflictDetected))
                    events))
           (repeated-actions
            (count (lambda (event)
                     (let ((payload (event-payload event)))
                       (and (cognitive-object? payload)
                            (evaluation-relation-ref payload 'repeated-action))))
                   conflicts))
           (outcome (process-outcome process))
           (elapsed-ms
            (* 1000.0
               (/ (- (get-internal-real-time) started)
                  internal-time-units-per-second)))
           (lifecycle-ok?
            (and (not (process-active? process))
                 (= (length terminals) 1)
                 (= (length finish-records) 1)
                 (eq? (caar finish-records) outcome)))
           (passed? (and lifecycle-ok? (eq? outcome 'COMPLETED))))
      `(("task" . ,(symbol->string (evaluation-task-id task)))
        ("category" . ,(symbol->string (evaluation-task-category task)))
        ("model" . ,model)
        ("repetition" . ,repetition)
        ("run_id" . ,case-id)
        ("passed" . ,passed?)
        ("lifecycle_ok" . ,lifecycle-ok?)
        ("outcome" . ,(if outcome (symbol->string outcome) "ACTIVE"))
        ("model_calls" . ,model-calls)
        ("execution_calls" . ,execution-calls)
        ("missing_actions" . ,(max 0 (- model-calls plans)))
        ("action_failures" . ,action-failures)
        ("verifier_conflicts" . ,(- (length conflicts) repeated-actions))
        ("repeated_actions" . ,repeated-actions)
        ("prompt_tokens" . ,prompt-tokens)
        ("completion_tokens" . ,completion-tokens)
        ("total_tokens" . ,total-tokens)
        ("latency_ms" . ,elapsed-ms)
        ("terminal_events" . ,(length terminals))
        ("finish_callbacks" . ,(length finish-records))
        ("responses" . ,(list->vector (reverse responses)))
        ("actions" . ,(list->vector (reverse actions)))
        ("adapter_errors" . ,(list->vector (reverse adapter-errors)))))))

(define* (run-evaluation-matrix tasks models repeats generate execute-factory)
  "Run every TASK x MODEL x repetition combination.
EXECUTE-FACTORY receives a unique run id and returns a fresh execution adapter."
  (unless (and (pair? tasks) (pair? models) (integer? repeats) (> repeats 0))
    (error "Evaluation matrix requires tasks, models and a positive repeat count"))
  (append-map
   (lambda (model)
     (append-map
      (lambda (task)
        (map
         (lambda (repetition)
           (let ((run-id (format #f "eval-~a-~a-~a"
                                 model (evaluation-task-id task) repetition)))
             (run-evaluation-case
              task model repetition generate (execute-factory run-id)
              #:run-id run-id)))
         (iota repeats 1)))
      tasks))
   models))

(define (summarize-evaluation-results results)
  (map
   (lambda (model)
     (let* ((model-results
             (filter (lambda (result)
                       (string=? (assoc-ref result "model") model))
                     results))
            (passed (count (lambda (result) (assoc-ref result "passed"))
                           model-results)))
       `(("model" . ,model)
         ("runs" . ,(length model-results))
         ("passed" . ,passed)
         ("success_rate" . ,(if (null? model-results)
                                 0.0
                                 (/ (* 100.0 passed) (length model-results))))
         ("lifecycle_failures" .
          ,(count (lambda (result) (not (assoc-ref result "lifecycle_ok")))
                  model-results))
         ("model_calls" .
          ,(fold + 0 (map (lambda (result) (assoc-ref result "model_calls"))
                          model-results)))
         ("execution_calls" .
          ,(fold + 0 (map (lambda (result) (assoc-ref result "execution_calls"))
                          model-results)))
         ("total_tokens" .
          ,(fold + 0 (map (lambda (result) (assoc-ref result "total_tokens"))
                          model-results)))
         ("latency_ms" .
          ,(fold + 0.0 (map (lambda (result) (assoc-ref result "latency_ms"))
                            model-results))))))
   (delete-duplicates (map (lambda (result) (assoc-ref result "model")) results)
                      string=?)))

(define (summarize-evaluation-cells results)
  "Aggregate the model x task cells without hiding task-specific failures."
  (append-map
   (lambda (model)
     (map
      (lambda (task)
        (let* ((cell-results
                (filter (lambda (result)
                          (and (string=? (assoc-ref result "model") model)
                               (string=? (assoc-ref result "task") task)))
                        results))
               (passed (count (lambda (result) (assoc-ref result "passed"))
                              cell-results))
               (repair-attempts
                (count (lambda (result) (> (assoc-ref result "model_calls") 1))
                       cell-results))
               (repair-successes
                (count (lambda (result)
                         (and (assoc-ref result "passed")
                              (> (assoc-ref result "model_calls") 1)))
                       cell-results)))
          `(("model" . ,model)
            ("task" . ,task)
            ("runs" . ,(length cell-results))
            ("passed" . ,passed)
            ("success_rate" . ,(/ (* 100.0 passed) (length cell-results)))
            ("first_pass_successes" .
             ,(count (lambda (result)
                       (and (assoc-ref result "passed")
                            (= (assoc-ref result "model_calls") 1)))
                     cell-results))
            ("repair_attempts" . ,repair-attempts)
            ("repair_successes" . ,repair-successes)
            ("missing_actions" .
             ,(fold + 0 (map (lambda (result) (assoc-ref result "missing_actions"))
                             cell-results)))
            ("action_failures" .
             ,(fold + 0 (map (lambda (result) (assoc-ref result "action_failures"))
                             cell-results)))
            ("repeated_actions" .
             ,(fold + 0 (map (lambda (result) (assoc-ref result "repeated_actions"))
                             cell-results)))
            ("lifecycle_failures" .
             ,(count (lambda (result) (not (assoc-ref result "lifecycle_ok")))
                     cell-results)))))
      (delete-duplicates
       (map (lambda (result) (assoc-ref result "task"))
            (filter (lambda (result)
                      (string=? (assoc-ref result "model") model))
                    results))
       string=?)))
   (delete-duplicates (map (lambda (result) (assoc-ref result "model")) results)
                      string=?)))
