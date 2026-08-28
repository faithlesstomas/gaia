(define-module (gaia goal-verifier)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (gaia com)
  #:use-module (gaia capability-registry)
  #:export (<goal-verdict>
            make-goal-verdict
            goal-verdict?
            goal-verdict-status
            goal-verdict-rationale
            goal-verdict-claim-content
            call-goal-verifier
            default-goal-verifier
            select-capability-manifest
            advertised-capability-manifests
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

(define production-capability-registry (make-default-capability-registry))

(define (advertised-capability-manifests)
  (filter capability-manifest-advertised?
          (registry-manifests production-capability-registry)))

(define (select-capability-manifest task)
  (registry-match production-capability-registry task))

(define (manifest-goal-verifier manifest)
  (lambda (goal action result evidence execution-claim state)
    (let ((verification
           (registry-verify manifest goal action result evidence
                            execution-claim state)))
      (make-goal-verdict
       (capability-verification-status verification)
       (capability-verification-rationale verification)
       (capability-verification-claim-content verification)))))

(define (select-goal-verifier task)
  "Select an independent verifier for TASK. Unknown task classes fail closed."
  (let ((manifest (select-capability-manifest task)))
    (if manifest (manifest-goal-verifier manifest) default-goal-verifier)))

(define (goal-completion-criteria task)
  "Return an executable acceptance contract for TASK."
  (let ((manifest (select-capability-manifest task)))
    (if manifest
        (capability-manifest-completion-criteria manifest)
        "Produce independently verified evidence that satisfies the user Goal.")))
