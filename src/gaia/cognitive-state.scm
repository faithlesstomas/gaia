(define-module (gaia cognitive-state)
  #:use-module (srfi srfi-9)
  #:use-module (ice-9 ftw)
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
            state-has-object?
            save-cognitive-state!
            load-cognitive-state))

;; Session-local source of truth for active cognitive objects and their event log.
;; Long-term memory is deliberately outside this minimal GCAS-Core state.
(define-record-type <cognitive-state>
  (%make-state objects-cell events-cell)
  cognitive-state?
  (objects-cell state-objects-cell)
  (events-cell state-events-cell))

(define* (make-cognitive-state #:key (objects '()) (events '()))
  (let ((state (%make-state (list '()) (list '()))))
    (for-each (lambda (co) (state-store! state co)) objects)
    (for-each (lambda (event) (state-record-event! state event)) events)
    state))

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

(define (event->alist event)
  `(("id" . ,(event-id event))
    ("type" . ,(symbol->string (event-type event)))
    ("origin" . ,(symbol->string (event-origin event)))
    ("timestamp" . ,(event-timestamp event))
    ("payload-kind" . ,(if (cognitive-object? (event-payload event)) "co" "raw"))
    ("payload" . ,(if (cognitive-object? (event-payload event))
                        (co->alist (event-payload event))
                        (event-payload event)))))

(define (alist->event alist)
  (let ((kind (assoc-ref alist "payload-kind"))
        (payload (assoc-ref alist "payload")))
    (make-cognitive-event
     (string->symbol (assoc-ref alist "type"))
     (if (string=? kind "co") (alist->co payload) payload)
     #:id (assoc-ref alist "id")
     #:origin (string->symbol (assoc-ref alist "origin"))
     #:timestamp (assoc-ref alist "timestamp"))))

(define (ensure-parent-directory! path)
  (let ((directory (dirname path)))
    (unless (file-exists? directory)
      (mkdir directory))))

(define (save-cognitive-state! state path)
  "Persist the auditable CO graph and chronological event log as local data."
  (ensure-parent-directory! path)
  (call-with-output-file path
    (lambda (port)
      (write `((objects . ,(map co->alist (state-objects state)))
               (events . ,(map event->alist (state-events state))))
             port)))
  path)

(define (load-cognitive-state path)
  "Restore a state saved by save-cognitive-state!, or return a clean state."
  (if (file-exists? path)
      (call-with-input-file path
        (lambda (port)
          (let ((data (read port)))
            (make-cognitive-state
             #:objects (map alist->co (assoc-ref data 'objects))
             #:events (map alist->event (assoc-ref data 'events))))))
      (make-cognitive-state)))
