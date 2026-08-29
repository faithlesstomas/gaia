(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (ice-9 format)
             (ice-9 match)
             (srfi srfi-1)
             (srfi srfi-13)
             (gaia config)
             (gaia core)
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

;; Live inference is intentionally opt-in. Ollama may retain model weights, so
;; a multi-model matrix can exhaust GPU/RAM even though runs are sequential.
(define resource-envelope
  (validate-live-resource-policy models resource-approved? model-parameters-b))

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

(format #t "GCAS live evaluation: endpoint=~a models=~s tasks=~s repeats=~a thinking=~a\n"
        (get-config 'llm-url) models (map evaluation-task-id tasks) repeats thinking?)
(format #t "Resource envelope: one-model-only=true parameters=~aB approved=~a\n"
        model-parameters-b resource-approved?)
(force-output)

(define results
  (run-evaluation-matrix tasks models repeats live-generate make-live-executor))
(define summary (summarize-evaluation-results results))
(define cells (summarize-evaluation-cells results))
(define interruption (run-interruption-readiness-check))
(define readiness
  (evaluate-readiness cells results interruption
                      #:minimum-repeats minimum-repeats
                      #:minimum-success-rate 80.0))

(for-each
 (lambda (result)
   (format #t "~a model=~a task=~a run=~a outcome=~a calls=~a exec=~a tokens=~a latency=~,1fms\n"
           (if (assoc-ref result "passed") "PASS" "FAIL")
           (assoc-ref result "model")
           (assoc-ref result "task")
           (assoc-ref result "repetition")
           (assoc-ref result "outcome")
           (assoc-ref result "model_calls")
           (assoc-ref result "execution_calls")
           (assoc-ref result "total_tokens")
           (assoc-ref result "latency_ms")))
 results)

(for-each
 (lambda (cell)
   (format #t "CELL model=~a task=~a passed=~a/~a success=~,1f% first-pass=~a repair=~a/~a missing=~a failures=~a repeated-actions=~a lifecycle-failures=~a\n"
           (assoc-ref cell "model")
           (assoc-ref cell "task")
           (assoc-ref cell "passed")
           (assoc-ref cell "runs")
           (assoc-ref cell "success_rate")
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
   (format #t "GATE model=~a task=~a ready=~a runs=~a success=~,1f% terminal=~,1f% false-completions=~a duplicate-exec=~a\n"
           (assoc-ref cell "model") (assoc-ref cell "task")
           (assoc-ref cell "ready") (assoc-ref cell "runs")
           (assoc-ref cell "success_rate") (assoc-ref cell "terminal_rate")
           (assoc-ref cell "false_completions")
           (assoc-ref cell "duplicate_executions")))
 (assoc-ref readiness "cells"))

(when (and output-path (not (string-null? (string-trim-both output-path))))
  (write-json-file
   output-path
   `(("schema_version" . 1)
     ("created_at" . ,(strftime "%Y-%m-%dT%H:%M:%S%z"
                                (localtime (current-time))))
     ("endpoint" . ,(get-config 'llm-url))
     ("models" . ,(list->vector models))
     ("tasks" . ,(list->vector (map (lambda (task)
                                      (symbol->string (evaluation-task-id task)))
                                    tasks)))
     ("repeats" . ,repeats)
     ("thinking" . ,thinking?)
     ("resource_envelope" . (("one_model_only" . #t)
                              ("model_parameters_b" . ,model-parameters-b)
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

(exit (if (and (every (lambda (result) (assoc-ref result "lifecycle_ok")) results)
               (or (not enforce-readiness?)
                   (string=? (assoc-ref readiness "status") "READY")))
          0 1))
