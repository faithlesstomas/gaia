(define-module (gaia workspace)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (gaia com)
  #:export (<global-workspace>
            make-global-workspace
            global-workspace?
            workspace-capacity
            workspace-candidates
            workspace-active
            workspace-propose!
            workspace-admit-next!
            workspace-retract!))

;; The workspace is bounded and separates proposal from admission.  A scheduler
;; calls workspace-admit-next! after Cognitive Control has selected a policy.
(define-record-type <global-workspace>
  (%make-workspace capacity candidates-cell active-cell)
  global-workspace?
  (capacity workspace-capacity)
  (candidates-cell workspace-candidates-cell)
  (active-cell workspace-active-cell))

(define* (make-global-workspace #:key (capacity 7))
  (unless (and (integer? capacity) (> capacity 0))
    (error "Workspace capacity must be a positive integer" capacity))
  (%make-workspace capacity (list '()) (list '())))

(define (workspace-candidates workspace)
  (map car (car (workspace-candidates-cell workspace))))

(define (workspace-active workspace)
  (reverse (car (workspace-active-cell workspace))))

(define* (workspace-propose! workspace co #:key (priority 0))
  (unless (cognitive-object? co)
    (error "Workspace proposals must be Cognitive Objects" co))
  (unless (number? priority)
    (error "Workspace priority must be numeric" priority))
  (let ((cell (workspace-candidates-cell workspace)))
    ;; Stable ordering makes equal-priority competition deterministic.
    (set-car! cell (append (car cell) (list (cons co priority)))))
  co)

(define (candidate-higher? left right)
  (> (cdr left) (cdr right)))

(define (workspace-admit-next! workspace)
  (let ((candidates (car (workspace-candidates-cell workspace)))
        (active (car (workspace-active-cell workspace))))
    (and (< (length active) (workspace-capacity workspace))
         (pair? candidates)
         (let* ((winner (fold (lambda (candidate best)
                                (if (candidate-higher? candidate best) candidate best))
                              (car candidates)
                              (cdr candidates)))
                (remaining (delq winner candidates))
                (co (car winner)))
           (set-car! (workspace-candidates-cell workspace) remaining)
           (set-car! (workspace-active-cell workspace) (cons co active))
           co))))

(define (workspace-retract! workspace object-id)
  (let ((active-cell (workspace-active-cell workspace))
        (candidate-cell (workspace-candidates-cell workspace)))
    (set-car! active-cell
              (filter (lambda (co) (not (equal? (co-id co) object-id))) (car active-cell)))
    (set-car! candidate-cell
              (filter (lambda (entry) (not (equal? (co-id (car entry)) object-id)))
                      (car candidate-cell)))
    object-id))
