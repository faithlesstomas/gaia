(define-module (gaia cognitive-control)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-1)
  #:use-module (gaia com)
  #:use-module (gaia workspace)
  #:export (<cognitive-control>
            make-cognitive-control
            cognitive-control?
            control-transition-count
            control-max-transitions
            control-max-stalled-transitions
            control-max-failures
            control-record-transition!
            control-record-progress!
            control-progress-count
            control-stalled-count
            control-record-failure!
            control-failure-count
            control-remaining-budgets
            control-request-interrupt!
            control-termination-reason
            control-select-candidate
            control-action-permitted?))

;; Minimal explicit control policy.  Richer scheduling and cost models can be
;; substituted without changing workspace or processor semantics.
(define-record-type <cognitive-control>
  (%make-control transitions-cell progress-cell stalled-cell failures-cell interrupted-cell
                 max-transitions max-stalled-transitions max-failures)
  cognitive-control?
  (transitions-cell control-transitions-cell)
  (progress-cell control-progress-cell)
  (stalled-cell control-stalled-cell)
  (failures-cell control-failures-cell)
  (interrupted-cell control-interrupted-cell)
  (max-transitions control-max-transitions)
  (max-stalled-transitions control-max-stalled-transitions)
  (max-failures control-max-failures))

(define* (make-cognitive-control #:key (max-transitions 32) (max-stalled-transitions 8)
                                (max-failures 3))
  (unless (every (lambda (value) (and (integer? value) (> value 0)))
                 (list max-transitions max-stalled-transitions max-failures))
    (error "control budgets must be positive integers"
           max-transitions max-stalled-transitions max-failures))
  (%make-control (list 0) (list 0) (list 0) (list 0) (list #f)
                 max-transitions max-stalled-transitions max-failures))

(define (control-transition-count control)
  (car (control-transitions-cell control)))

(define (control-record-transition! control)
  (let ((cell (control-transitions-cell control)))
    (set-car! cell (+ 1 (car cell))))
  (let ((cell (control-stalled-cell control)))
    (set-car! cell (+ 1 (car cell))))
  (control-transition-count control))

(define (control-progress-count control)
  (car (control-progress-cell control)))

(define (control-stalled-count control)
  (car (control-stalled-cell control)))

(define (control-record-progress! control)
  "Register an externally observable state advance, not an LLM confidence claim."
  (let ((cell (control-progress-cell control)))
    (set-car! cell (+ 1 (car cell))))
  (set-car! (control-stalled-cell control) 0)
  (control-progress-count control))

(define (control-failure-count control)
  (car (control-failures-cell control)))

(define (control-remaining-budgets control)
  `((transitions . ,(max 0 (- (control-max-transitions control)
                              (control-transition-count control))))
    (stalled-transitions . ,(max 0 (- (control-max-stalled-transitions control)
                                      (control-stalled-count control))))
    (failures . ,(max 0 (- (control-max-failures control)
                           (control-failure-count control))))))

(define (control-record-failure! control)
  (let ((cell (control-failures-cell control)))
    (set-car! cell (+ 1 (car cell))))
  (control-failure-count control))

(define (control-request-interrupt! control)
  (set-car! (control-interrupted-cell control) #t)
  'USER_INTERRUPTED)

(define (control-termination-reason control)
  (cond
   ((car (control-interrupted-cell control)) 'USER_INTERRUPTED)
   ((>= (control-transition-count control) (control-max-transitions control))
    'BUDGET_EXHAUSTED)
   ((>= (control-failure-count control) (control-max-failures control))
    'FAILURE_BUDGET_EXHAUSTED)
   ((>= (car (control-stalled-cell control)) (control-max-stalled-transitions control))
    'NO_PROGRESS)
   (else #f)))

(define (control-candidate-score candidate)
  "A transparent baseline policy for GCAS-Core.  Priority is explicit intent;
the other fields penalize proposals that are less relevant, more risky, more
expensive, or less certain.  Equal scores preserve submission order."
  (+ (candidate-priority candidate)
     (* 10 (candidate-relevance candidate))
     (* 10 (candidate-urgency candidate))
     (* 5 (candidate-risk candidate))
     (* 15 (candidate-conflict candidate))
     (* 20 (candidate-out-of-domain candidate))
     (* 15 (candidate-information-gain candidate))
     (* -10 (candidate-risk candidate))
     (* -10 (candidate-cost candidate))))

(define (control-select-candidate control candidates)
  "Choose one pending workspace candidate under the current Control policy."
  (let loop ((best (car candidates)) (rest (cdr candidates)))
    (if (null? rest)
        best
        (let ((next (car rest)))
          (loop (if (> (control-candidate-score next)
                       (control-candidate-score best))
                    next
                    best)
                (cdr rest))))))

(define (control-action-permitted? action-co)
  ;; Proposal is not deployment: only an explicit Action CO can reach an
  ;; execution processor.  Capability/policy checks extend this predicate.
  (and (cognitive-object? action-co)
       (eq? (co-type action-co) 'action)))
