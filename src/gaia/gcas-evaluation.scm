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
            make-behavior-evaluation-task
            evaluation-task-id
            evaluation-task-category
            evaluation-task-prompt
            default-live-evaluation-tasks
            select-evaluation-tasks
            run-evaluation-case
            run-evaluation-matrix
            summarize-evaluation-results
            summarize-evaluation-cells
            validate-live-resource-policy
            run-interruption-readiness-check
            evaluate-readiness
            readiness-json-object))

;; Live evaluation tasks are deliberately independent from a model provider.
;; Their acceptance boundary consumes only the executed Action and Result COs.

(define* (validate-live-resource-policy models approved? model-parameters-b
                                        #:key (max-model-parameters-b 4.0))
  "Enforce the operator's local inference envelope before contacting an endpoint."
  (unless (and (list? models) (= (length models) 1))
    (error "Resource policy permits exactly one live-evaluation model" models))
  (unless approved?
    (error "Live evaluation requires explicit per-run operator approval"))
  (unless (and (number? model-parameters-b) (> model-parameters-b 0))
    (error "Live evaluation requires the model's actual parameter count"))
  (unless (and (number? max-model-parameters-b)
               (> max-model-parameters-b 0))
    (error "Live evaluation requires a positive operator parameter limit"))
  (when (> model-parameters-b max-model-parameters-b)
    (error "Live evaluation model exceeds the operator's parameter limit"
           (car models) model-parameters-b max-model-parameters-b))
  `((one-model-only . #t) (model . ,(car models))
    (model-parameters-b . ,model-parameters-b) (operator-approved . #t)))

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

(define* (make-behavior-evaluation-task id category prompt binding probes
                                        #:key
                                        (completion-criteria
                                         "The named procedure must satisfy its public contract for independently selected inputs. Hidden tests must pass.")
                                        (max-transitions 32)
                                        (max-stalled-transitions 8)
                                        (max-failures 3)
                                        (max-replans 3))
  "Construct an eval-v2 task.  PROBES receives repetition and execution-attempt
and returns expression/expected pairs.  Neither probes nor oracle values are
projected into model or repair prompts."
  (unless (and (symbol? id) (symbol? category) (string? prompt)
               (symbol? binding) (procedure? probes)
               (string? completion-criteria))
    (error "Invalid GCAS behavioral evaluation task" id category prompt))
  `((id . ,id)
    (category . ,category)
    (prompt . ,prompt)
    (evaluation-version . 2)
    (oracle-class . HIDDEN_PROPERTY_TESTS)
    (required-binding . ,binding)
    (probe-builder . ,probes)
    (completion-criteria . ,completion-criteria)
    (max-transitions . ,max-transitions)
    (max-stalled-transitions . ,max-stalled-transitions)
    (max-failures . ,max-failures)
    (max-replans . ,max-replans)))

(define (evaluation-task-id task) (assoc-ref task 'id))
(define (evaluation-task-category task) (assoc-ref task 'category))
(define (evaluation-task-prompt task) (assoc-ref task 'prompt))

(define (rotate values offset)
  (let* ((size (length values))
         (split (if (= size 0) 0 (modulo offset size))))
    (append (drop values split) (take values split))))

(define (select-hidden-probes bank repetition attempt)
  "Select a deterministic, repetition-seeded base suite.  A repair is checked
against additional holdout probes that were not exercised by its predecessor."
  (let* ((ordered (rotate bank (- repetition 1)))
         (base (take ordered (min 3 (length ordered))))
         (holdout (take (rotate bank (+ repetition 2))
                        (min 2 (length bank)))))
    (if (> attempt 1) (delete-duplicates (append base holdout) equal?) base)))

(define (factorial-value n)
  (let loop ((value n) (acc 1))
    (if (= value 0) acc (loop (- value 1) (* acc value)))))

(define (fibonacci-values n)
  (let loop ((remaining n) (a 0) (b 1) (result '()))
    (if (= remaining 0)
        (reverse result)
        (loop (- remaining 1) b (+ a b) (cons a result)))))

(define (input-probes bank expression expected repetition attempt)
  (map (lambda (input) (list (expression input) (expected input)))
       (select-hidden-probes bank repetition attempt)))

(define default-live-evaluation-tasks
  (list
   (make-behavior-evaluation-task
    'arithmetic-42 'arithmetic-procedure
    "Define a Guile Scheme procedure (solve-arithmetic a b c) that computes (a * b) - c for arbitrary numeric arguments. The evaluator will call it on independently selected inputs."
    'solve-arithmetic
    (lambda (repetition attempt)
      (input-probes
       '((17 3 9) (8 -4 3) (0 91 -7) (-6 -5 11) (23 2 19) (5 5 25)
         (101 0 -13) (-12 7 -4) (9 9 80) (31 -2 -62) (4 13 17) (-9 -9 5))
       (lambda (args) `(solve-arithmetic ,@args))
       (lambda (args) (- (* (car args) (cadr args)) (caddr args)))
       repetition attempt))
    #:completion-criteria
    "Define solve-arithmetic with three parameters. It must compute (a * b) - c for arbitrary numeric inputs and pass hidden deterministic tests.")
   (make-behavior-evaluation-task
    'map-squares 'list-transform
    "Define a Guile Scheme procedure (square-all xs) that returns a list containing the square of every number in xs, preserving order. The evaluator will call it on independently selected lists."
    'square-all
    (lambda (repetition attempt)
      (input-probes
       '(() (1 2 3) (-3 0 4) (7) (2 -5 11 -1) (10 20)
         (0 0 0) (-1 -2 -3 -4) (13 21) (6 -8 10) (100) (3 1 4 1 5))
       (lambda (xs) `(square-all ',xs))
       (lambda (xs) (map (lambda (value) (* value value)) xs))
       repetition attempt)))
   (make-behavior-evaluation-task
    'filter-evens 'list-filter
    "Define a Guile Scheme procedure (keep-evens xs) that returns only the even integers from xs, preserving order. The evaluator will call it on independently selected lists."
    'keep-evens
    (lambda (repetition attempt)
      (input-probes
       '(() (1 3 5) (2 4 6) (-4 -3 -2 -1 0) (11 8 7 14) (42)
         (-7 -5 -3) (0 1 2) (100 101 -102) (9 12 15 18) (-1 1) (6 6 7 8))
       (lambda (xs) `(keep-evens ',xs))
       (lambda (xs) (filter even? xs))
       repetition attempt)))
   (make-behavior-evaluation-task
    'factorial-6 'procedure
    "Define a recursive Guile Scheme procedure (factorial n) for non-negative integers, with 0! = 1. The evaluator will call it on independently selected inputs."
    'factorial
    (lambda (repetition attempt)
      (input-probes '(0 1 2 3 4 5 6 7 8 9 10 11)
                    (lambda (n) `(factorial ,n)) factorial-value
                    repetition attempt)))
   (make-behavior-evaluation-task
    'fibonacci-10 'procedure
    "Define a Guile Scheme procedure (fibonacci-sequence n) that returns the first n Fibonacci terms, starting with 0 and 1. It must handle every non-negative n. The evaluator will call it on independently selected inputs."
    'fibonacci-sequence
    (lambda (repetition attempt)
      (input-probes '(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)
                    (lambda (n) `(fibonacci-sequence ,n)) fibonacci-values
                    repetition attempt)))))

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

(define (unit-test-summary value)
  (and (list? value)
       (let ((passed (assoc-ref value 'passed))
             (failed (assoc-ref value 'failed))
             (total (assoc-ref value 'total)))
         (and (integer? passed) (>= passed 0)
              (integer? failed) (>= failed 0)
              (integer? total) (> total 0)
              (= (+ passed failed) total)
              `((passed . ,passed) (failed . ,failed) (total . ,total))))))

(define (behavior-task? task)
  (eq? (assoc-ref task 'oracle-class) 'HIDDEN_PROPERTY_TESTS))

(define (behavior-harness task repetition attempt)
  "Return a private test harness appended only at the execution boundary.
The original Action and all model-visible contexts remain probe-free."
  (let* ((probes ((assoc-ref task 'probe-builder) repetition attempt))
         (checks (map (lambda (probe)
                        `(equal? ,(car probe) ',(cadr probe)))
                      probes)))
    (format #f
            "\n(let* ((gaia-eval-v2-checks (list ~{~s~^ ~}))\n       (gaia-eval-v2-passed (let loop ((rest gaia-eval-v2-checks) (count 0))\n                              (if (null? rest) count\n                                  (loop (cdr rest)\n                                        (if (car rest) (+ count 1) count)))))\n       (gaia-eval-v2-total (length gaia-eval-v2-checks)))\n  `((passed . ,gaia-eval-v2-passed)\n    (failed . ,(- gaia-eval-v2-total gaia-eval-v2-passed))\n    (total . ,gaia-eval-v2-total)))"
            checks)))

(define (task-verifier task)
  (lambda (goal action result evidence execution-claim state)
    (let* ((parsed (read-single-datum (co-content result)))
           (binding (assoc-ref task 'required-binding))
           (action-ok? (or (not binding)
                           (action-defines-binding? (co-content action) binding)))
           (summary (and parsed (behavior-task? task)
                         (unit-test-summary (cdr parsed))))
           (result-ok? (if (behavior-task? task)
                           (and summary (= (assoc-ref summary 'failed) 0))
                           (and parsed
                                (equal? (cdr parsed) (assoc-ref task 'expected))))))
      (if (and action-ok? result-ok?)
          (make-goal-verdict
           'SATISFIED
           (if (behavior-task? task)
               "The independent hidden behavioral test suite accepted the executed procedure."
               "The independent live-evaluation oracle accepted the executed Result.")
           (if (behavior-task? task)
               (format #f "Verified hidden tests: ~a passed."
                       (assoc-ref summary 'passed))
               (format #f "Verified result: ~s" (assoc-ref task 'expected))))
          (make-goal-verdict
           'REJECTED
           (string-append
            (if action-ok? "" "The required procedure definition was not observed. ")
            (if (behavior-task? task)
                "The implementation did not satisfy the hidden behavioral contract. Return a complete, general procedure; hidden inputs and oracle values are not disclosed."
                (format #f "Expected final datum ~s, observed ~s."
                        (assoc-ref task 'expected)
                        (and parsed (cdr parsed))))))))))

(define (metadata-ref metadata key)
  (let ((value (and (list? metadata)
                    (or (assoc-ref metadata key)
                        (assoc-ref metadata (symbol->string key))))))
    (if (number? value) value 0)))

(define (evaluation-relation-ref co key)
  (assoc-ref (co-relations co) key))

(define (notify-evaluation-observer observer type payload)
  "Deliver a non-semantic evaluation diagnostic; observer failure is isolated."
  (when observer
    (catch #t
      (lambda () (observer type payload))
      (lambda _ #f))))

(define* (run-evaluation-case task model repetition generate execute
                              #:key (run-id #f) (observer #f)
                              (trace-sink #f) (diagnostic-sink #f))
  "Run one TASK/MODEL/REPETITION through the production GCAS processor.

GENERATE receives MODEL, RUN-ID, cognitive PROMPT, SUCCESS and FAILURE.
SUCCESS accepts response text and optional metadata. EXECUTE uses the normal
production callback contract. This injection boundary keeps the matrix
provider- and runtime-agnostic."
  (let* ((case-id (or run-id
                      (format #f "eval-~a-~a-~a"
                              model (evaluation-task-id task) repetition)))
         (session (make-cognitive-session
                   #:workspace-capacity 8 #:restore? #f
                   #:trace-sink trace-sink
                   #:diagnostic-sink diagnostic-sink))
         (model-calls 0)
         (execution-calls 0)
         (prompt-tokens 0)
         (completion-tokens 0)
         (total-tokens 0)
         (responses '())
         (actions '())
         (hidden-tests-passed? #f)
         (hidden-tests-run 0)
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
             (let ((call-number model-calls)
                   (call-started (get-internal-real-time)))
               (notify-evaluation-observer
                observer 'ModelCallStarted
                `((run-id . ,case-id) (model . ,model)
                  (call . ,call-number) (context . ,context)))
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
                      (notify-evaluation-observer
                       observer 'ModelCallCompleted
                       `((run-id . ,case-id) (model . ,model)
                         (call . ,call-number) (response . ,response)
                         (metadata . ,metadata)
                         (latency-ms . ,(* 1000.0
                                          (/ (- (get-internal-real-time)
                                                call-started)
                                             internal-time-units-per-second)))))
                      (succeed response))
                    (lambda (message)
                      (set! adapter-errors
                            (cons (format #f "~a" message) adapter-errors))
                      (notify-evaluation-observer
                       observer 'ModelCallFailed
                       `((run-id . ,case-id) (model . ,model)
                         (call . ,call-number) (error . ,(format #f "~a" message))))
                      (fail (format #f "~a" message)))))
                 (lambda (key . args)
                   (let ((message (format #f "~a ~s" key args)))
                     (set! adapter-errors (cons message adapter-errors))
                     (notify-evaluation-observer
                      observer 'ModelCallFailed
                      `((run-id . ,case-id) (model . ,model)
                        (call . ,call-number) (error . ,message)))
                     (fail message))))))
           #:extract-action
           (lambda (response)
             ;; The caller supplies model text, while the production extractor
             ;; remains the same adapter used by the server.
             (extract-gcas-action response))
           #:execute
           (lambda (code succeed fail)
             (set! execution-calls (+ execution-calls 1))
             (set! actions (cons code actions))
             (notify-evaluation-observer
              observer 'ExecutionStarted
              `((run-id . ,case-id) (call . ,execution-calls) (action . ,code)))
             (catch #t
               (lambda ()
                 (let ((executed-code
                        (if (behavior-task? task)
                            (string-append code
                                           (behavior-harness task repetition
                                                             execution-calls))
                            code)))
                 (execute
                  executed-code
                  (lambda (result)
                    (when (behavior-task? task)
                      (let* ((parsed (read-single-datum result))
                             (summary (and parsed
                                           (unit-test-summary (cdr parsed)))))
                        (when summary
                          (set! hidden-tests-run
                                (+ hidden-tests-run (assoc-ref summary 'total)))
                          (set! hidden-tests-passed?
                                (= (assoc-ref summary 'failed) 0)))))
                    (notify-evaluation-observer
                     observer 'ExecutionCompleted
                     `((run-id . ,case-id) (call . ,execution-calls)
                       (action . ,code) (result . ,result)))
                    (succeed result))
                  (lambda (type message)
                    (notify-evaluation-observer
                     observer 'ExecutionFailed
                     `((run-id . ,case-id) (call . ,execution-calls)
                       (action . ,code) (error-type . ,type)
                       (error . ,message)))
                    (fail type message)))))
               (lambda (key . args)
                 (let ((message (format #f "~a ~s" key args)))
                   (set! adapter-errors (cons message adapter-errors))
                   (notify-evaluation-observer
                    observer 'ExecutionFailed
                    `((run-id . ,case-id) (call . ,execution-calls)
                      (action . ,code) (error-type . runtime)
                      (error . ,message)))
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
      (let ((result
             `(("task" . ,(symbol->string (evaluation-task-id task)))
        ("category" . ,(symbol->string (evaluation-task-category task)))
        ("model" . ,model)
        ("repetition" . ,repetition)
        ("run_id" . ,case-id)
        ("passed" . ,passed?)
        ("lifecycle_ok" . ,lifecycle-ok?)
        ("action_executed" . ,(> execution-calls 0))
        ("hidden_tests_passed" . ,(and (behavior-task? task)
                                        hidden-tests-passed?))
        ("hidden_tests_run" . ,hidden-tests-run)
        ("probe_seed" . ,repetition)
        ("repair_holdout_applied" . ,(and (behavior-task? task)
                                           (> execution-calls 1)))
        ("evaluation_version" . ,(or (assoc-ref task 'evaluation-version) 1))
        ("outcome" . ,(if outcome (symbol->string outcome) "ACTIVE"))
        ("model_calls" . ,model-calls)
        ("execution_calls" . ,execution-calls)
        ("missing_actions" . ,(max 0 (- model-calls plans)))
        ("action_failures" . ,action-failures)
        ("verifier_conflicts" . ,(- (length conflicts) repeated-actions))
        ("repeated_actions" . ,repeated-actions)
        ("duplicate_executions" .
         ,(- (length actions) (length (delete-duplicates actions string=?))))
        ("false_completions" .
         ,(if (and (eq? outcome 'COMPLETED) (not passed?)) 1 0))
        ("prompt_tokens" . ,prompt-tokens)
        ("completion_tokens" . ,completion-tokens)
        ("total_tokens" . ,total-tokens)
        ("latency_ms" . ,elapsed-ms)
        ("terminal_events" . ,(length terminals))
        ("finish_callbacks" . ,(length finish-records))
        ("responses" . ,(list->vector (reverse responses)))
        ("actions" . ,(list->vector (reverse actions)))
               ("adapter_errors" . ,(list->vector (reverse adapter-errors))))))
        result))))

(define* (run-evaluation-matrix tasks models repeats generate execute-factory
                                #:key (observer #f)
                                (trace-sink-factory #f)
                                (diagnostic-sink-factory #f))
  "Run every TASK x MODEL x repetition combination.
EXECUTE-FACTORY receives a unique run id and returns a fresh execution adapter."
  (unless (and (pair? tasks) (pair? models) (integer? repeats) (> repeats 0))
    (error "Evaluation matrix requires tasks, models and a positive repeat count"))
  (let ((index 0)
        (total (* (length tasks) (length models) repeats)))
    (append-map
     (lambda (model)
       (append-map
        (lambda (task)
          (map
           (lambda (repetition)
             (let ((run-id (format #f "eval-~a-~a-~a"
                                   model (evaluation-task-id task) repetition)))
               (set! index (+ index 1))
               (notify-evaluation-observer
                observer 'CaseStarted
                `((run-id . ,run-id) (index . ,index) (total . ,total)
                  (model . ,model) (task . ,(evaluation-task-id task))
                  (repetition . ,repetition)))
               (let ((result
                      (run-evaluation-case
                       task model repetition generate (execute-factory run-id)
                       #:run-id run-id #:observer observer
                       #:trace-sink (and trace-sink-factory
                                          (trace-sink-factory run-id))
                       #:diagnostic-sink
                       (and diagnostic-sink-factory
                            (diagnostic-sink-factory run-id)))))
                 (notify-evaluation-observer
                  observer 'CaseCompleted
                  `((run-id . ,run-id) (index . ,index) (total . ,total)
                    (result . ,result)))
                 result)))
           (iota repeats 1)))
        tasks))
     models)))

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

(define* (run-interruption-readiness-check #:key (max-latency-ms 100.0))
  "Exercise the real synchronous process interruption boundary and a late model
callback.  This is model-free because interruption correctness must not depend
on endpoint responsiveness."
  (let ((session (make-cognitive-session #:workspace-capacity 2))
        (late-success #f) (executions 0) (finishes '()))
    (start-production-process!
     session "Interrupt this readiness probe."
     #:generate (lambda (prompt succeed fail) (set! late-success succeed))
     #:extract-action extract-gcas-action
     #:execute (lambda args (set! executions (+ executions 1)))
     #:on-finished (lambda (outcome final-text hypothesis-text)
                     (set! finishes (cons outcome finishes))))
    (let ((started (get-internal-real-time)))
      (session-request-interrupt! session)
      (let ((latency (* 1000.0
                        (/ (- (get-internal-real-time) started)
                           internal-time-units-per-second))))
        (when late-success (late-success "```repl\n42\n```"))
        (let* ((terminals
                (count (lambda (event)
                         (memq (event-type event)
                               '(GoalCompleted ProcessTerminated)))
                       (state-events (session-state session))))
               (passed (and (= terminals 1) (= (length finishes) 1)
                            (eq? (car finishes) 'USER_INTERRUPTED)
                            (= executions 0) (<= latency max-latency-ms))))
          `(("passed" . ,passed) ("latency_ms" . ,latency)
            ("max_latency_ms" . ,max-latency-ms)
            ("terminal_events" . ,terminals)
            ("finish_callbacks" . ,(length finishes))
            ("post_terminal_executions" . ,executions)))))))

(define* (evaluate-readiness cells results interruption
                             #:key (minimum-repeats 10)
                             (minimum-success-rate 80.0)
                             (required-evaluation-version 2))
  "Apply release thresholds per capability cell; aggregate averages cannot
hide a failing task."
  (let* ((cell-gates
          (map
           (lambda (cell)
             (let* ((model (assoc-ref cell "model"))
                    (task (assoc-ref cell "task"))
                    (cell-results
                     (filter (lambda (result)
                               (and (string=? (assoc-ref result "model") model)
                                    (string=? (assoc-ref result "task") task)))
                             results))
                    (false-completions
                     (fold + 0 (map (lambda (result)
                                      (assoc-ref result "false_completions"))
                                    cell-results)))
                    (duplicate-executions
                     (fold + 0 (map (lambda (result)
                                      (assoc-ref result "duplicate_executions"))
                                    cell-results)))
                    (invalid-verifications
                     (count
                      (lambda (result)
                        (or (not (= (assoc-ref result "evaluation_version")
                                    required-evaluation-version))
                            (and (= required-evaluation-version 2)
                                 (assoc-ref result "passed")
                                 (not (assoc-ref result
                                                 "hidden_tests_passed")))))
                      cell-results))
                    (ready (and (>= (assoc-ref cell "runs") minimum-repeats)
                                (= (assoc-ref cell "lifecycle_failures") 0)
                                (= false-completions 0)
                                (= duplicate-executions 0)
                                (= invalid-verifications 0)
                                (>= (assoc-ref cell "success_rate")
                                    minimum-success-rate))))
               `(("model" . ,model) ("task" . ,task) ("ready" . ,ready)
                 ("runs" . ,(assoc-ref cell "runs"))
                 ("success_rate" . ,(assoc-ref cell "success_rate"))
                 ("terminal_rate" .
                  ,(* 100.0 (/ (- (assoc-ref cell "runs")
                                  (assoc-ref cell "lifecycle_failures"))
                               (assoc-ref cell "runs"))))
                 ("false_completions" . ,false-completions)
                 ("invalid_verifications" . ,invalid-verifications)
                 ("duplicate_executions" . ,duplicate-executions))))
           cells))
         (ready (and (pair? cell-gates)
                     (every (lambda (cell) (assoc-ref cell "ready")) cell-gates)
                     (assoc-ref interruption "passed"))))
    `(("status" . ,(if ready "READY" "NOT_READY"))
      ("minimum_repeats" . ,minimum-repeats)
      ("minimum_success_rate" . ,minimum-success-rate)
      ("required_evaluation_version" . ,required-evaluation-version)
      ("interruption" . ,interruption)
      ("cells" . ,cell-gates))))

(define (readiness-json-object readiness)
  "Project a readiness result to guile-json's object/array representation."
  (map (lambda (entry)
         (if (string=? (car entry) "cells")
             (cons "cells" (list->vector (cdr entry)))
             entry))
       readiness))

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
            ("actions_executed" .
             ,(count (lambda (result) (assoc-ref result "action_executed"))
                     cell-results))
            ("hidden_test_successes" .
             ,(count (lambda (result)
                       (assoc-ref result "hidden_tests_passed"))
                     cell-results))
            ("hidden_tests_run" .
             ,(fold + 0 (map (lambda (result)
                               (assoc-ref result "hidden_tests_run"))
                             cell-results)))
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
