(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (srfi srfi-1)
             (srfi srfi-64)
             (gaia gcas-evaluation))

(test-begin "gaia-gcas-live-evaluation")

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

(test-equal "both model identifiers reach the injected adapter"
  '("model-a" "model-b")
  (sort (delete-duplicates seen-models string=?) string<?))

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
