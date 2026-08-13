(define-module (gaia cognitive-state)
  #:use-module (srfi srfi-9)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:export (<cognitive-state>
            make-cognitive-state
            cognitive-state?
            state-store!
            state-find
            state-objects
            state-record-event!
            state-events
            state-active-goals
            state-has-object?))

;; Session-local source of truth for active cognitive objects and their event log.
;; Long-term memory is deliberately outside this minimal GCAS-Core state.
(define-record-type <cognitive-state>
  (%make-state objects-cell events-cell)
  cognitive-state?
  (objects-cell state-objects-cell)
  (events-cell state-events-cell))

(define (make-cognitive-state)
  (%make-state (list '()) (list '())))

(define (state-objects state)
  (map cdr (reverse (car (state-objects-cell state)))))

(define (state-find state co-id)
  (let ((entry (assoc co-id (car (state-objects-cell state)))))
    (and entry (cdr entry))))

(define (state-has-object? state co-id)
  (and (state-find state co-id) #t))

(define (state-store! state co)
  (unless (cognitive-object? co)
    (error "Cognitive State can only store Cognitive Objects" co))
  (let ((cell (state-objects-cell state)))
    (set-car! cell (acons (co-id co)
                          co
                          (filter (lambda (entry)
                                    (not (equal? (car entry) (co-id co))))
                                  (car cell)))))
  co)

(define (state-record-event! state event)
  (unless (cognitive-event? event)
    (error "Cognitive State can only record Cognitive Events" event))
  (let ((cell (state-events-cell state)))
    (set-car! cell (cons event (car cell))))
  event)

(define (state-events state)
  (reverse (car (state-events-cell state))))

(define (state-active-goals state)
  (filter (lambda (co) (eq? (co-type co) 'goal)) (state-objects state)))
