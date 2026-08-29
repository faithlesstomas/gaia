(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (ice-9 format)
             (ice-9 match)
             (ice-9 threads)
             (srfi srfi-1)
             (srfi srfi-13)
             (gaia config)
             (gaia core)
             (gaia cognitive-trace)
             (gaia executor)
             (gaia gcas-evaluation)
             (gaia llm-client)
             (gaia rlm-env)
             (gaia utils))

(define (env-list name fallback)
  (let ((value (getenv name)))
    (if (and value (not (string-null? (string-trim-both value))))
        (filter (lambda (item) (not (string-null? item)))
                (map string-trim-both (string-split value #\,)))
        fallback)))

(define (env-positive-integer name fallback)
  (let* ((value (getenv name))
         (parsed (and value (string->number value))))
    (if (and (integer? parsed) (> parsed 0)) parsed fallback)))

(define (env-positive-number name)
  (let* ((value (getenv name))
         (parsed (and value (string->number value))))
    (and (number? parsed) (> parsed 0) parsed)))

(define (env-nonnegative-integer name fallback)
  (let* ((value (getenv name))
         (parsed (and value (string->number value))))
    (if (and (integer? parsed) (>= parsed 0)) parsed fallback)))

(define (env-boolean name fallback)
  (let ((value (getenv name)))
    (if value
        (member (string-downcase (string-trim-both value))
                '("1" "true" "yes" "on"))
        fallback)))

(load-config)

(define models (env-list "GAIA_EVAL_MODELS" (list (get-config 'model))))
(define task-ids
  (map string->symbol (env-list "GAIA_EVAL_TASKS" '())))
(define tasks (select-evaluation-tasks default-live-evaluation-tasks task-ids))
(define repeats (env-positive-integer "GAIA_EVAL_REPEATS" 1))
(define thinking? (and (env-boolean "GAIA_EVAL_THINKING" #f) #t))
(define output-path (getenv "GAIA_EVAL_OUTPUT"))
(define enforce-readiness? (and (env-boolean "GAIA_EVAL_ENFORCE_READINESS" #f) #t))
(define minimum-repeats (env-positive-integer "GAIA_EVAL_MIN_REPEATS" 10))
(define resource-approved? (and (env-boolean "GAIA_EVAL_RESOURCE_APPROVED" #f) #t))
(define model-parameters-b (env-positive-number "GAIA_EVAL_MODEL_PARAMETERS_B"))
(define max-model-parameters-b
  (or (env-positive-number "GAIA_EVAL_MAX_MODEL_PARAMETERS_B") 4.0))
(define verbosity (env-nonnegative-integer "GAIA_EVAL_VERBOSE" 0))
(define heartbeat-seconds
  (env-positive-integer "GAIA_EVAL_HEARTBEAT_SECONDS" 10))
(define preview-chars (env-positive-integer "GAIA_EVAL_PREVIEW_CHARS" 240))
(define trace-output-path (getenv "GAIA_EVAL_TRACE_OUTPUT"))

(when (> verbosity 3)
  (error "GAIA_EVAL_VERBOSE must be an integer from 0 through 3" verbosity))
(when (and output-path trace-output-path
           (not (string-null? (string-trim-both output-path)))
           (string=? output-path trace-output-path))
  (error "GAIA_EVAL_OUTPUT and GAIA_EVAL_TRACE_OUTPUT must be different files"
         output-path))

(define log-mutex (make-mutex))
(define trace-port
  (and (>= verbosity 1)
       trace-output-path
       (not (string-null? (string-trim-both trace-output-path)))
       (open-file trace-output-path "w")))

(define (evaluation-timestamp)
  (strftime "%Y-%m-%dT%H:%M:%S%z" (localtime (current-time))))

(define* (evaluation-log minimum-level kind message #:optional (extra '()))
  (when (>= verbosity minimum-level)
    (with-mutex log-mutex
      (format #t "[~a] [~a] ~a\n" (evaluation-timestamp) kind message)
      (force-output)
      (when trace-port
        (display
         (scm->json
          (append `(("timestamp" . ,(evaluation-timestamp))
                    ("kind" . ,kind)
                    ("message" . ,message))
                  extra))
         trace-port)
        (newline trace-port)
        (force-output trace-port)))))

(define (preview value)
  (trace-preview value preview-chars))

(define active-heartbeat #f)

(define (deadline-after seconds)
  (let ((now (gettimeofday)))
    (cons (+ (car now) seconds) (cdr now))))

(define (stop-heartbeat!)
  (when active-heartbeat
    (match active-heartbeat
      ((thread mutex condition done-cell started run-id call-number)
       (with-mutex mutex
         (set-car! done-cell #t)
         (signal-condition-variable condition))
       (join-thread thread)
       (set! active-heartbeat #f)))))

(define (start-heartbeat! run-id call-number)
  (stop-heartbeat!)
  (when (>= verbosity 1)
    (let* ((mutex (make-mutex))
           (condition (make-condition-variable))
           (done-cell (list #f))
           (started (get-internal-real-time))
           (thread
            (call-with-new-thread
             (lambda ()
               (lock-mutex mutex)
               (let loop ()
                 (let ((signaled?
                        (wait-condition-variable
                         condition mutex (deadline-after heartbeat-seconds))))
                   (cond
                    ((car done-cell) (unlock-mutex mutex))
                    (signaled? (loop))
                    (else
                     (unlock-mutex mutex)
                     (evaluation-log
                      1 "WAIT"
                      (format #f
                              "run=~a model-call=~a elapsed=~,1fs waiting-for=LiteLLM"
                              run-id call-number
                              (/ (- (get-internal-real-time) started)
                                 (* 1.0 internal-time-units-per-second))))
                     (lock-mutex mutex)
                     (loop)))))))))
      (set! active-heartbeat
            (list thread mutex condition done-cell started run-id call-number)))))

(define (metadata-value metadata key)
  (or (assoc-ref metadata key)
      (assoc-ref metadata (symbol->string key))
      0))

(define (make-evaluation-observer)
  (lambda (type payload)
    (case type
      ((CaseStarted)
       (evaluation-log
        1 "CASE"
        (format #f "~a/~a START run=~a model=~a task=~a repetition=~a"
                (assoc-ref payload 'index) (assoc-ref payload 'total)
                (assoc-ref payload 'run-id) (assoc-ref payload 'model)
                (assoc-ref payload 'task) (assoc-ref payload 'repetition))))
      ((ModelCallStarted)
       (let ((run-id (assoc-ref payload 'run-id))
             (call-number (assoc-ref payload 'call)))
         (evaluation-log
          1 "LLM"
          (format #f "START run=~a call=~a model=~a endpoint=~a"
                  run-id call-number (assoc-ref payload 'model)
                  (get-config 'llm-url)))
         (evaluation-log
          3 "PROMPT" (assoc-ref payload 'context)
          `(("run_id" . ,run-id) ("call" . ,call-number)
            ("content" . ,(assoc-ref payload 'context))))
         (start-heartbeat! run-id call-number)))
      ((ModelCallCompleted)
       (stop-heartbeat!)
       (let ((metadata (assoc-ref payload 'metadata)))
         (evaluation-log
          1 "LLM"
          (format #f "END run=~a call=~a latency=~,1fms tokens=~a"
                  (assoc-ref payload 'run-id) (assoc-ref payload 'call)
                  (assoc-ref payload 'latency-ms)
                  (metadata-value metadata 'total_tokens))))
       (evaluation-log
        3 "RESPONSE" (assoc-ref payload 'response)
        `(("run_id" . ,(assoc-ref payload 'run-id))
          ("call" . ,(assoc-ref payload 'call))
          ("content" . ,(assoc-ref payload 'response)))))
      ((ModelCallFailed)
       (stop-heartbeat!)
       (evaluation-log
        1 "LLM-ERROR"
        (format #f "run=~a call=~a error=~a"
                (assoc-ref payload 'run-id) (assoc-ref payload 'call)
                (assoc-ref payload 'error))))
      ((ExecutionStarted)
       (evaluation-log
        1 "EXEC"
        (format #f "START run=~a call=~a action=~a"
                (assoc-ref payload 'run-id) (assoc-ref payload 'call)
                (preview (assoc-ref payload 'action))))
       (evaluation-log
        3 "ACTION" (assoc-ref payload 'action)
        `(("run_id" . ,(assoc-ref payload 'run-id))
          ("call" . ,(assoc-ref payload 'call))
          ("content" . ,(assoc-ref payload 'action)))))
      ((ExecutionCompleted)
       (evaluation-log
        1 "EXEC"
        (format #f "END run=~a call=~a result=~a"
                (assoc-ref payload 'run-id) (assoc-ref payload 'call)
                (preview (assoc-ref payload 'result))))
       (evaluation-log
        3 "RESULT" (format #f "~a" (assoc-ref payload 'result))
        `(("run_id" . ,(assoc-ref payload 'run-id))
          ("call" . ,(assoc-ref payload 'call))
          ("content" . ,(format #f "~a" (assoc-ref payload 'result))))))
      ((ExecutionFailed)
       (evaluation-log
        1 "EXEC-ERROR"
        (format #f "run=~a call=~a type=~a error=~a"
                (assoc-ref payload 'run-id) (assoc-ref payload 'call)
                (assoc-ref payload 'error-type) (assoc-ref payload 'error))))
      ((CaseCompleted)
       (let ((result (assoc-ref payload 'result)))
         (evaluation-log
          1 "CASE"
          (format #f "~a/~a END run=~a status=~a outcome=~a latency=~,1fms"
                  (assoc-ref payload 'index) (assoc-ref payload 'total)
                  (assoc-ref payload 'run-id)
                  (if (assoc-ref result "passed") "PASS" "FAIL")
                  (assoc-ref result "outcome")
                  (assoc-ref result "latency_ms"))
          `(("run_id" . ,(assoc-ref payload 'run-id))
            ("result" . ,result))))))))

(define (make-evaluation-trace-sink run-id)
  (make-cognitive-trace-sink
   run-id
   (lambda (message) (evaluation-log 2 "EVENT" message))
   #:preview-chars preview-chars))

(define (make-evaluation-diagnostic-sink run-id)
  (lambda (session type payload)
    (evaluation-log
     3 "PROCESSOR"
     (format #f "run=~a diagnostic=~a processor=~a event=~a proposals=~a details=~s"
             run-id type (assoc-ref payload 'processor)
             (assoc-ref payload 'event-type)
             (or (assoc-ref payload 'proposal-count) "-") payload))))

;; Live inference is intentionally opt-in. Ollama may retain model weights, so
;; a multi-model matrix can exhaust GPU/RAM even though runs are sequential.
(define resource-envelope
  (validate-live-resource-policy models resource-approved? model-parameters-b
                                 #:max-model-parameters-b
                                 max-model-parameters-b))

(define (live-generate model run-id context succeed fail)
  (let* ((response (chat-with-llm run-id context model (get-gcas-system-prompt)
                                  #:think thinking? #:history '()))
         (payload (assoc-ref response "payload"))
         (error-text (assoc-ref response "error"))
         (usage (or (assoc-ref response "usage") '())))
    (if (and payload (not error-text))
        (succeed (assoc-ref payload "content") usage)
        (fail (if error-text
                  (format #f "~a" error-text)
                  (format #f "Invalid LLM response: ~s" response))))))

(define (make-live-executor run-id)
  (let ((env (make-rlm-env run-id #f (lambda (_) #f))))
    (lambda (code succeed fail)
      (match (rlm-execute env code #:permission-handler (lambda (_) #f))
        (('ok value) (succeed value))
        (('error type message) (fail type message))
        (other (fail 'runtime (format #f "Invalid execution response: ~s" other)))))))

(format #t "GCAS live evaluation v2: endpoint=~a models=~s tasks=~s repeats=~a thinking=~a oracle=hidden-property-tests\n"
        (get-config 'llm-url) models (map evaluation-task-id tasks) repeats thinking?)
(format #t "Resource envelope: one-model-only=true parameters=~aB max=~aB approved=~a\n"
        model-parameters-b max-model-parameters-b resource-approved?)
(format #t "Observability: verbose=~a heartbeat=~as trace=~a LiteLLM-log=.litellm.log\n"
        verbosity heartbeat-seconds
        (if trace-port trace-output-path "disabled"))
(force-output)

(define results
  (run-evaluation-matrix
   tasks models repeats live-generate make-live-executor
   #:observer (and (>= verbosity 1) (make-evaluation-observer))
   #:trace-sink-factory (and (>= verbosity 2) make-evaluation-trace-sink)
   #:diagnostic-sink-factory
   (and (>= verbosity 3) make-evaluation-diagnostic-sink)))
(stop-heartbeat!)
(define summary (summarize-evaluation-results results))
(define cells (summarize-evaluation-cells results))
(define interruption (run-interruption-readiness-check))
(define readiness
  (evaluate-readiness cells results interruption
                      #:minimum-repeats minimum-repeats
                      #:minimum-success-rate 80.0))

(for-each
 (lambda (result)
   (format #t "~a model=~a task=~a run=~a outcome=~a lifecycle=~a action-executed=~a hidden-tests=~a/~a calls=~a exec=~a tokens=~a latency=~,1fms\n"
           (if (assoc-ref result "passed") "PASS" "FAIL")
           (assoc-ref result "model")
           (assoc-ref result "task")
           (assoc-ref result "repetition")
           (assoc-ref result "outcome")
           (assoc-ref result "lifecycle_ok")
           (assoc-ref result "action_executed")
           (assoc-ref result "hidden_tests_passed")
           (assoc-ref result "hidden_tests_run")
           (assoc-ref result "model_calls")
           (assoc-ref result "execution_calls")
           (assoc-ref result "total_tokens")
           (assoc-ref result "latency_ms")))
 results)

(for-each
 (lambda (cell)
   (format #t "CELL model=~a task=~a passed=~a/~a success=~,1f% hidden-success=~a tests=~a action-runs=~a first-pass=~a repair=~a/~a missing=~a failures=~a repeated-actions=~a lifecycle-failures=~a\n"
           (assoc-ref cell "model")
           (assoc-ref cell "task")
           (assoc-ref cell "passed")
           (assoc-ref cell "runs")
           (assoc-ref cell "success_rate")
           (assoc-ref cell "hidden_test_successes")
           (assoc-ref cell "hidden_tests_run")
           (assoc-ref cell "actions_executed")
           (assoc-ref cell "first_pass_successes")
           (assoc-ref cell "repair_successes")
           (assoc-ref cell "repair_attempts")
           (assoc-ref cell "missing_actions")
           (assoc-ref cell "action_failures")
           (assoc-ref cell "repeated_actions")
           (assoc-ref cell "lifecycle_failures")))
 cells)

(for-each
 (lambda (item)
   (format #t "SUMMARY model=~a passed=~a/~a success=~,1f% lifecycle-failures=~a calls=~a exec=~a tokens=~a latency=~,1fms\n"
           (assoc-ref item "model")
           (assoc-ref item "passed")
           (assoc-ref item "runs")
           (assoc-ref item "success_rate")
           (assoc-ref item "lifecycle_failures")
           (assoc-ref item "model_calls")
           (assoc-ref item "execution_calls")
           (assoc-ref item "total_tokens")
           (assoc-ref item "latency_ms")))
 summary)

(format #t "READINESS status=~a min-repeats=~a interruption=~a latency=~,3fms\n"
        (assoc-ref readiness "status")
        (assoc-ref readiness "minimum_repeats")
        (assoc-ref interruption "passed")
        (assoc-ref interruption "latency_ms"))
(for-each
 (lambda (cell)
   (format #t "GATE model=~a task=~a ready=~a runs=~a success=~,1f% terminal=~,1f% invalid-verifications=~a false-completions=~a duplicate-exec=~a\n"
           (assoc-ref cell "model") (assoc-ref cell "task")
           (assoc-ref cell "ready") (assoc-ref cell "runs")
           (assoc-ref cell "success_rate") (assoc-ref cell "terminal_rate")
           (assoc-ref cell "invalid_verifications")
           (assoc-ref cell "false_completions")
           (assoc-ref cell "duplicate_executions")))
 (assoc-ref readiness "cells"))

(when (and output-path (not (string-null? (string-trim-both output-path))))
  (write-json-file
   output-path
   `(("schema_version" . 2)
     ("evaluation_contract" . "gcas-live-eval-v2-hidden-property-tests")
     ("created_at" . ,(strftime "%Y-%m-%dT%H:%M:%S%z"
                                (localtime (current-time))))
     ("endpoint" . ,(get-config 'llm-url))
     ("models" . ,(list->vector models))
     ("tasks" . ,(list->vector (map (lambda (task)
                                      (symbol->string (evaluation-task-id task)))
                                    tasks)))
     ("repeats" . ,repeats)
     ("thinking" . ,thinking?)
     ("verbose" . ,verbosity)
     ("heartbeat_seconds" . ,heartbeat-seconds)
     ("trace_output" . ,(and trace-port trace-output-path))
     ("resource_envelope" . (("one_model_only" . #t)
                              ("model_parameters_b" . ,model-parameters-b)
                              ("max_model_parameters_b" . ,max-model-parameters-b)
                              ("operator_approved" . ,resource-approved?)))
     ("readiness" . ,(readiness-json-object readiness))
     ("system_prompt_source" . ,(if (getenv "GAIA_SYSTEM_PROMPT")
                                      "GAIA_SYSTEM_PROMPT"
                                      "GCAS_SYSTEM_PROMPT"))
     ("system_prompt" . ,(get-gcas-system-prompt))
     ("summary" . ,(list->vector summary))
     ("cells" . ,(list->vector cells))
     ("results" . ,(list->vector results))))
  (format #t "Wrote JSON report to ~a\n" output-path))

(when trace-port
  (close-port trace-port)
  (format #t "Wrote incremental trace to ~a\n" trace-output-path))

(exit (if (and (every (lambda (result) (assoc-ref result "lifecycle_ok")) results)
               (or (not enforce-readiness?)
                   (string=? (assoc-ref readiness "status") "READY")))
          0 1))
