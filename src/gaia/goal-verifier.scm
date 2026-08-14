(define-module (gaia goal-verifier)
  #:use-module (srfi srfi-9)
  #:use-module (gaia com)
  #:export (<goal-verdict>
            make-goal-verdict
            goal-verdict?
            goal-verdict-status
            goal-verdict-rationale
            goal-verdict-claim-content
            call-goal-verifier
            default-goal-verifier))

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
