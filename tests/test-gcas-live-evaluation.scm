(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (ice-9 eval-string)
             (srfi srfi-1)
             (srfi srfi-64)
             (gaia cognitive-bus)
             (gaia gcas-evaluation)
             (gaia utils))

(test-begin "gaia-gcas-live-evaluation")

(test-assert "live resource policy requires one approved model at or below 4B"
  (and (equal? (assoc-ref (validate-live-resource-policy '("qwen3:4b") #t 4.0)
                          'model)
               "qwen3:4b")
       (catch #t
         (lambda () (validate-live-resource-policy '("a" "b") #t 1.0) #f)
         (lambda _ #t))
       (catch #t
         (lambda () (validate-live-resource-policy '("qwen3:4b") #f 4.0) #f)
         (lambda _ #t))
       (catch #t
         (lambda () (validate-live-resource-policy '("gemma4:e2b") #t 5.1) #f)
         (lambda _ #t))
       (equal? (assoc-ref
                (validate-live-resource-policy
                 '("qwen3.5-4b") #t 4.7
                 #:max-model-parameters-b 4.7)
                'model)
               "qwen3.5-4b")))

(define offline-tasks
  (list
   (make-datum-evaluation-task 'answer-a 'exact "Return 42." 42)
   (make-datum-evaluation-task 'answer-b 'list "Return (2 4)." '(2 4))))

(test-equal "task selection preserves corpus order"
  '(answer-a answer-b)
  (map evaluation-task-id
       (select-evaluation-tasks offline-tasks '(answer-b answer-a))))

(define seen-models '())

(define (mock-generate model run-id context succeed fail)
  (set! seen-models (cons model seen-models))
  (if (string-contains context "Return 42.")
      (succeed "```repl\n42\n```"
               '(("prompt_tokens" . 10)
                 ("completion_tokens" . 3)
                 ("total_tokens" . 13)))
      (succeed "```repl\n'(2 4)\n```"
               '(("prompt_tokens" . 11)
                 ("completion_tokens" . 4)
                 ("total_tokens" . 15)))))

(define (mock-execute-factory run-id)
  (lambda (code succeed fail)
    (if (string-contains code "42")
        (succeed "42")
        (succeed "(2 4)"))))

(define offline-results
  (run-evaluation-matrix offline-tasks '("model-a" "model-b") 2
                         mock-generate mock-execute-factory))
(define offline-summary (summarize-evaluation-results offline-results))
(define offline-cells (summarize-evaluation-cells offline-results))

(test-equal "matrix is the Cartesian product of models, tasks and repetitions"
  8 (length offline-results))

(test-assert "all offline runs use production verification and lifecycle"
  (every (lambda (result)
           (and (assoc-ref result "passed")
                (assoc-ref result "lifecycle_ok")
                (= (assoc-ref result "terminal_events") 1)
                (= (assoc-ref result "finish_callbacks") 1)))
         offline-results))

(test-assert "readiness fails closed below repetitions and passes per capable cell"
  (let* ((interruption (run-interruption-readiness-check))
         (not-ready (evaluate-readiness offline-cells offline-results interruption))
         (ready (evaluate-readiness offline-cells offline-results interruption
                                    #:minimum-repeats 2
                                    #:required-evaluation-version 1)))
    (and (assoc-ref interruption "passed")
         (string=? (assoc-ref not-ready "status") "NOT_READY")
         (string=? (assoc-ref ready "status") "READY")
         (every (lambda (result)
                  (and (= (assoc-ref result "false_completions") 0)
                       (= (assoc-ref result "duplicate_executions") 0)))
                offline-results))))

(test-assert "readiness cells serialize as a JSON array"
  (let* ((readiness
          (evaluate-readiness offline-cells offline-results
                              (run-interruption-readiness-check)))
         (encoded (scm->json (readiness-json-object readiness)))
         (decoded (json->scm encoded)))
    (and (vector? (assoc-ref decoded "cells"))
         (= (vector-length (assoc-ref decoded "cells")) 4))))

(test-assert "evaluation observability reports progress, GCAS events and processor routing"
  (let ((observations '()) (event-traces '()) (processor-traces '()))
    (let ((observed-results
           (run-evaluation-matrix
            (list (car offline-tasks)) '("observed-model") 1
            mock-generate mock-execute-factory
            #:observer
            (lambda (type payload)
              (set! observations (cons type observations)))
            #:trace-sink-factory
            (lambda (run-id)
              (lambda (session event)
                (set! event-traces (cons (event-type event) event-traces))))
            #:diagnostic-sink-factory
            (lambda (run-id)
              (lambda (session type payload)
                (set! processor-traces (cons type processor-traces)))))))
      (and (assoc-ref (car observed-results) "passed")
           (every (lambda (type) (memq type observations))
                  '(CaseStarted ModelCallStarted ModelCallCompleted
                    ExecutionStarted ExecutionCompleted CaseCompleted))
           (memq 'WorkspaceBroadcast event-traces)
           (memq 'ProcessorReceived processor-traces)
           (memq 'ProcessorReturned processor-traces)))))

(test-assert "diagnostic observer failures cannot change evaluation outcome"
  (assoc-ref
   (run-evaluation-case
    (car offline-tasks) "observer-failure" 1
    mock-generate (mock-execute-factory "observer-failure")
    #:observer (lambda args (error "diagnostic observer failed")))
   "passed"))

(test-assert "both matrix model identifiers reach the injected adapter"
  (every (lambda (model) (member model seen-models))
         '("model-a" "model-b")))

(test-assert "summary is separated by model and includes usage"
  (and (= (length offline-summary) 2)
       (every (lambda (item)
                (and (= (assoc-ref item "runs") 4)
                     (= (assoc-ref item "passed") 4)
                     (= (assoc-ref item "success_rate") 100.0)
                     (= (assoc-ref item "total_tokens") 56)))
              offline-summary)))

(test-assert "cell summary keeps model and task axes separate"
  (and (= (length offline-cells) 4)
       (every (lambda (cell)
                (and (= (assoc-ref cell "runs") 2)
                     (= (assoc-ref cell "passed") 2)
                     (= (assoc-ref cell "first_pass_successes") 2)
                     (= (assoc-ref cell "repair_attempts") 0)
                     (= (assoc-ref cell "missing_actions") 0)
                     (= (assoc-ref cell "action_failures") 0)
                     (= (assoc-ref cell "repeated_actions") 0)))
              offline-cells)))

(define procedure-task
  (make-datum-evaluation-task
   'procedure-shapes 'procedure "Define factorial and return 720." 720
   #:required-binding 'factorial))

(define procedure-results
  (run-evaluation-matrix
   (list procedure-task) '("define-sugar" "lambda-binding") 1
   (lambda (model run-id context succeed fail)
     (succeed
      (if (string=? model "define-sugar")
          "```repl\n(define (factorial n) (if (= n 0) 1 (* n (factorial (- n 1)))))\n(factorial 6)\n```"
          "```repl\n(define factorial (lambda (n) (if (= n 0) 1 (* n (factorial (- n 1))))))\n(factorial 6)\n```")))
   (lambda (run-id)
     (lambda (code succeed fail) (succeed "720")))))

(test-assert "procedure oracle accepts both canonical Scheme definition forms"
  (every (lambda (result) (assoc-ref result "passed")) procedure-results))

(define (scheme-evaluation-executor code succeed fail)
  (catch #t
    (lambda ()
      (let ((value (eval-string code #:module (make-fresh-user-module))))
        (succeed (call-with-output-string
                   (lambda (port) (write value port))))))
    (lambda (key . args)
      (fail 'runtime (format #f "~a ~s" key args)))))

(define fibonacci-v2
  (car (select-evaluation-tasks default-live-evaluation-tasks
                                '(fibonacci-10))))

(define hardcoded-fibonacci-result
  (run-evaluation-case
   fibonacci-v2 "hardcoded" 1
   (lambda (model run-id context succeed fail)
     (succeed
      "```repl\n(define (fibonacci-sequence n) '(0 1 1 2 3 5 8 13 21 34))\n(fibonacci-sequence 10)\n```"))
   scheme-evaluation-executor))

(test-assert "eval v2 rejects the previously accepted hardcoded Fibonacci list"
  (and (not (assoc-ref hardcoded-fibonacci-result "passed"))
       (assoc-ref hardcoded-fibonacci-result "action_executed")
       (not (assoc-ref hardcoded-fibonacci-result "hidden_tests_passed"))
       (> (assoc-ref hardcoded-fibonacci-result "hidden_tests_run") 0)))

(define hardcoded-v1-actions
  `((arithmetic-42 . "(define (solve-arithmetic a b c) 42)\n(solve-arithmetic 17 3 9)")
    (map-squares . "(define (square-all xs) '(1 4 9 16 25))\n(square-all '(1 2 3 4 5))")
    (filter-evens . "(define (keep-evens xs) '(2 4 6 8 10))\n(keep-evens '(1 2 3 4 5 6 7 8 9 10))")
    (factorial-6 . "(define (factorial n) 720)\n(factorial 6)")
    (fibonacci-10 . "(define (fibonacci-sequence n) '(0 1 1 2 3 5 8 13 21 34))\n(fibonacci-sequence 10)")))

(define hardcoded-v1-results
  (map
   (lambda (task)
     (let ((action-text (assoc-ref hardcoded-v1-actions
                                   (evaluation-task-id task))))
       (run-evaluation-case
        task "v1-shortcut" 1
        (lambda (model run-id context succeed fail)
          (succeed (string-append "```repl\n" action-text "\n```")))
        scheme-evaluation-executor)))
   default-live-evaluation-tasks))

(test-assert "all five former fixed-answer shortcuts fail hidden behavioral tests"
  (every (lambda (result)
           (and (not (assoc-ref result "passed"))
                (assoc-ref result "action_executed")
                (not (assoc-ref result "hidden_tests_passed"))))
         hardcoded-v1-results))

(define repaired-fibonacci-responses
  (list
   "```repl\n(define (fibonacci-sequence n) '(0 1 1 2 3 5 8 13 21 34))\n(fibonacci-sequence 10)\n```"
   "```repl\n(define (fibonacci-sequence n)\n  (let loop ((remaining n) (a 0) (b 1) (result '()))\n    (if (= remaining 0)\n        (reverse result)\n        (loop (- remaining 1) b (+ a b) (cons a result)))))\n(fibonacci-sequence 10)\n```"))

(define repaired-fibonacci-result
  (run-evaluation-case
   fibonacci-v2 "repair" 1
   (lambda (model run-id context succeed fail)
     (let ((response (car repaired-fibonacci-responses)))
       (set! repaired-fibonacci-responses (cdr repaired-fibonacci-responses))
       (succeed response)))
   scheme-evaluation-executor))

(test-assert "repair must pass a larger fresh hidden holdout"
  (and (assoc-ref repaired-fibonacci-result "passed")
       (assoc-ref repaired-fibonacci-result "hidden_tests_passed")
       (= (assoc-ref repaired-fibonacci-result "model_calls") 2)
       (> (assoc-ref repaired-fibonacci-result "hidden_tests_run") 3)))

(test-assert "model-visible eval v2 contract does not disclose Fibonacci oracle values"
  (let ((prompt (evaluation-task-prompt fibonacci-v2)))
    (and (not (string-contains prompt "0 1 1 2 3 5 8 13 21 34"))
         (not (string-contains prompt "720")))))

(define repeated-result
  (run-evaluation-case
   (make-datum-evaluation-task 'repeat-metric 'control "Return 42." 42
                               #:max-replans 1)
   "repeater" 1
   (lambda (model run-id context succeed fail)
     (succeed "```scheme\n41\n```"))
   (lambda (code succeed fail) (succeed "41"))))

(test-assert "live metrics distinguish verifier conflict and repeated Action"
  (and (not (assoc-ref repeated-result "passed"))
       (= (assoc-ref repeated-result "verifier_conflicts") 1)
       (= (assoc-ref repeated-result "repeated_actions") 1)
       (= (assoc-ref repeated-result "action_failures") 0)))

(let* ((runner (test-runner-current))
       (failures (if runner (test-runner-fail-count runner) 0)))
  (test-end "gaia-gcas-live-evaluation")
  (exit (if (> failures 0) 1 0)))
