(define-module (gaia workspace)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (gaia com)
  #:export (<global-workspace>
            <workspace-candidate>
            make-global-workspace
            global-workspace?
            workspace-capacity
            workspace-candidates
            workspace-candidate-entries
            candidate-co
            candidate-priority
            candidate-relevance
            candidate-risk
            candidate-cost
            candidate-uncertainty
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

;; A proposal carries decision metadata separately from the immutable CO.  This
;; lets Control change scheduling policy without mutating evidence or claims.
(define-record-type <workspace-candidate>
  (%make-candidate co priority relevance risk cost uncertainty)
  workspace-candidate?
  (co candidate-co)
  (priority candidate-priority)
  (relevance candidate-relevance)
  (risk candidate-risk)
  (cost candidate-cost)
  (uncertainty candidate-uncertainty))

(define* (make-global-workspace #:key (capacity 7))
  (unless (and (integer? capacity) (> capacity 0))
    (error "Workspace capacity must be a positive integer" capacity))
  (%make-workspace capacity (list '()) (list '())))

(define (workspace-candidates workspace)
  (map candidate-co (car (workspace-candidates-cell workspace))))

(define (workspace-candidate-entries workspace)
  "Return pending proposals with their scheduling metadata in submission order."
  (car (workspace-candidates-cell workspace)))

(define (workspace-active workspace)
  (reverse (car (workspace-active-cell workspace))))

(define (valid-decision-value? value label)
  (unless (and (number? value) (>= value 0))
    (error (format #f "~a must be a non-negative number" label) value)))

(define* (workspace-propose! workspace co
                            #:key
                            (priority 0)
                            (relevance 0)
                            (risk 0)
                            (cost 0)
                            (uncertainty 0))
  (unless (cognitive-object? co)
    (error "Workspace proposals must be Cognitive Objects" co))
  (for-each (lambda (pair) (valid-decision-value? (cdr pair) (car pair)))
            `((priority . ,priority)
              (relevance . ,relevance)
              (risk . ,risk)
              (cost . ,cost)
              (uncertainty . ,uncertainty)))
  (let ((cell (workspace-candidates-cell workspace)))
    ;; Stable ordering makes equal-score competition deterministic.
    (set-car! cell
              (append (car cell)
                      (list (%make-candidate co priority relevance risk cost uncertainty)))))
  co)

(define (default-candidate-score candidate)
  ;; Priority is the explicit operator/processor preference.  The remaining
  ;; terms make selection inspect goal relevance and the expected safety and
  ;; resource consequences of executing a proposal.
  (+ (candidate-priority candidate)
     (* 10 (candidate-relevance candidate))
     (* -10 (candidate-risk candidate))
     (* -10 (candidate-cost candidate))
     (* -10 (candidate-uncertainty candidate))))

(define* (workspace-admit-next! workspace #:key (selector #f))
  (let ((candidates (car (workspace-candidates-cell workspace)))
        (active (car (workspace-active-cell workspace))))
    (and (< (length active) (workspace-capacity workspace))
         (pair? candidates)
         (let* ((choose (or selector
                            (lambda (entries)
                              (fold (lambda (candidate best)
                                      (if (> (default-candidate-score candidate)
                                             (default-candidate-score best))
                                          candidate
                                          best))
                                    (car entries)
                                    (cdr entries)))))
                (winner (choose candidates)))
           (unless (and (workspace-candidate? winner)
                        (memq winner candidates))
             (error "Workspace selector must return a pending candidate" winner))
           (let* ((remaining (delq winner candidates))
                  (co (candidate-co winner)))
             (set-car! (workspace-candidates-cell workspace) remaining)
             (set-car! (workspace-active-cell workspace) (cons co active))
             co)))))

(define (workspace-retract! workspace object-id)
  (let ((active-cell (workspace-active-cell workspace))
        (candidate-cell (workspace-candidates-cell workspace)))
    (set-car! active-cell
              (filter (lambda (co) (not (equal? (co-id co) object-id))) (car active-cell)))
    (set-car! candidate-cell
              (filter (lambda (entry) (not (equal? (co-id (candidate-co entry)) object-id)))
                      (car candidate-cell)))
    object-id))
