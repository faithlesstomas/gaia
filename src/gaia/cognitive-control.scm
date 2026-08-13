(define-module (gaia cognitive-control)
  #:use-module (srfi srfi-9)
  #:use-module (gaia com)
  #:use-module (gaia workspace)
  #:export (<cognitive-control>
            make-cognitive-control
            cognitive-control?
            control-transition-count
            control-max-transitions
            control-record-transition!
            control-termination-reason
            control-select-candidate
            control-action-permitted?))

;; Minimal explicit control policy.  Richer scheduling and cost models can be
;; substituted without changing workspace or processor semantics.
(define-record-type <cognitive-control>
  (%make-control transitions-cell max-transitions)
  cognitive-control?
  (transitions-cell control-transitions-cell)
  (max-transitions control-max-transitions))

(define* (make-cognitive-control #:key (max-transitions 32))
  (unless (and (integer? max-transitions) (> max-transitions 0))
    (error "max-transitions must be a positive integer" max-transitions))
  (%make-control (list 0) max-transitions))

(define (control-transition-count control)
  (car (control-transitions-cell control)))

(define (control-record-transition! control)
  (let ((cell (control-transitions-cell control)))
    (set-car! cell (+ 1 (car cell))))
  (control-transition-count control))

(define (control-termination-reason control)
  (and (>= (control-transition-count control) (control-max-transitions control))
       'BUDGET_EXHAUSTED))

(define (control-candidate-score candidate)
  "A transparent baseline policy for GCAS-Core.  Priority is explicit intent;
the other fields penalize proposals that are less relevant, more risky, more
expensive, or less certain.  Equal scores preserve submission order."
  (+ (candidate-priority candidate)
     (* 10 (candidate-relevance candidate))
     (* -10 (candidate-risk candidate))
     (* -10 (candidate-cost candidate))
     (* -10 (candidate-uncertainty candidate))))

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
