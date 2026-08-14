(define-module (gaia goal-verifier)
  #:use-module (ice-9 regex)
  #:use-module (srfi srfi-9)
  #:use-module (gaia com)
  #:export (<goal-verdict>
            make-goal-verdict
            goal-verdict?
            goal-verdict-status
            goal-verdict-rationale
            goal-verdict-claim-content
            call-goal-verifier
            default-goal-verifier
            select-goal-verifier
            goal-completion-criteria))

;; Goal verification is deliberately a separate, injected decision boundary.
;; A generative processor may propose Actions and a deliberative processor may
;; establish execution evidence, but neither may declare the user Goal complete.
(define-record-type <goal-verdict>
  (%make-goal-verdict status rationale claim-content)
  goal-verdict?
  (status goal-verdict-status)
  (rationale goal-verdict-rationale)
  (claim-content goal-verdict-claim-content))

(define (valid-verdict-status? status)
  (memq status '(SATISFIED REJECTED INCONCLUSIVE)))

(define* (make-goal-verdict status rationale #:optional claim-content)
  (unless (and (valid-verdict-status? status) (string? rationale)
               (> (string-length rationale) 0))
    (error "A Goal verdict requires a status and non-empty rationale" status rationale))
  (%make-goal-verdict status rationale (or claim-content rationale)))

(define (call-goal-verifier verifier goal action result evidence execution-claim state)
  "Call an independent GOAL verifier and validate its result.

VERIFIER receives only explicit Cognitive Objects and State.  It must return a
<goal-verdict>; plain booleans and LLM text cannot satisfy a Goal accidentally."
  (unless (and (procedure? verifier) (cognitive-object? goal)
               (cognitive-object? action) (cognitive-object? result)
               (cognitive-object? evidence) (cognitive-object? execution-claim))
    (error "Invalid Goal verifier inputs" verifier goal action result evidence execution-claim))
  (let ((verdict (verifier goal action result evidence execution-claim state)))
    (unless (goal-verdict? verdict)
      (error "Goal verifier must return a <goal-verdict>" verdict))
    verdict))

(define (default-goal-verifier goal action result evidence execution-claim state)
  "Safe default for arbitrary natural-language Goals.

Without a task-specific independent criterion, a successful execution proves
only its bounded observation and must not become GoalCompleted."
  (make-goal-verdict
   'INCONCLUSIVE
   "No independent Goal verifier was supplied for this task."))

(define fibonacci-pattern
  (make-regexp "0[^0-9]+1[^0-9]+1[^0-9]+2[^0-9]+3[^0-9]+5[^0-9]+8[^0-9]+13[^0-9]+21[^0-9]+34"))

(define (fibonacci-goal? task)
  (let ((text (string-downcase (format #f "~a" task))))
    (or (string-contains text "fibonacci")
        (string-contains text "fibonacciego"))))

(define (fibonacci-goal-verifier goal action result evidence execution-claim state)
  "Verify the observable contract used by the production Fibonacci capability.

The generated Action must return the first ten terms.  The verifier consumes
the REPL Result, never the LLM's assertion that its implementation is correct."
  (if (and (string-contains (co-content action) "(define (fibonacci-sequence")
           (regexp-exec fibonacci-pattern (co-content result)))
      (make-goal-verdict
       'SATISFIED
       "The deterministic Fibonacci verifier observed the required procedure and first ten terms."
       (string-append
        "Verified Scheme implementation:\n```scheme\n"
        (co-content action)
        "\n```\nObserved result: `(0 1 1 2 3 5 8 13 21 34)`."))
      (make-goal-verdict
       'REJECTED
       (string-append
        "Expected the Action to define fibonacci-sequence and its result to contain "
        "the first ten Fibonacci terms: "
        "0 1 1 2 3 5 8 13 21 34. The observed result did not match; revise the "
        "implementation and return the sequence as the final Scheme value."))))

(define (select-goal-verifier task)
  "Select an independent verifier for TASK. Unknown task classes fail closed."
  (if (fibonacci-goal? task)
      fibonacci-goal-verifier
      default-goal-verifier))

(define (goal-completion-criteria task)
  "Return an executable acceptance contract for TASK."
  (if (fibonacci-goal? task)
      (string-append
       "Define a fibonacci-sequence procedure and make the final Scheme "
       "expression return its first ten terms exactly as "
       "(0 1 1 2 3 5 8 13 21 34). An independent deterministic verifier must "
       "accept the observed Result.")
      "Produce independently verified evidence that satisfies the user Goal."))
