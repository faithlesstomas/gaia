(define-module (gaia cognitive-bus)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (ice-9 match)
  #:use-module (gaia com)
  #:export (<cognitive-event>
            make-cognitive-event
            cognitive-event?
            event-id
            event-type
            event-payload
            event-origin
            event-timestamp
            
            ;; Specialized Event Constructors
            make-goal-created-event
            make-hypothesis-proposed-event
            make-action-requested-event
            make-action-completed-event
            make-action-failed-event
            make-conflict-detected-event
            make-reflection-raised-event

            ;; Cognitive Bus
            <cognitive-bus>
            make-cognitive-bus
            cognitive-bus?
            bus-subscribe
            bus-publish
            bus-retract
            bus-supersede
            bus-events-history))

;; Cognitive Event Record
(define-record-type <cognitive-event>
  (%make-event id type payload origin timestamp)
  cognitive-event?
  (id event-id)
  (type event-type)
  (payload event-payload)
  (origin event-origin)
  (timestamp event-timestamp))

(define (generate-event-id)
  (format #f "evt-~a-~a" (current-time) (random 1000000)))

(define* (make-cognitive-event type payload #:key (id #f) (origin 'KERNEL) (timestamp #f))
  "Constructs a typed Cognitive Event carrying a Cognitive Object or semantic payload."
  (let ((evt-id (or id (generate-event-id)))
        (evt-time (or timestamp (current-time))))
    (%make-event evt-id type payload origin evt-time)))

;; Specialized Event Constructors
(define* (make-goal-created-event goal-co #:optional (origin #f))
  (make-cognitive-event 'GoalCreated goal-co #:origin (or origin (co-provenance goal-co))))

(define (make-hypothesis-proposed-event hyp-co)
  (make-cognitive-event 'HypothesisProposed hyp-co #:origin 'LLM))

(define (make-action-requested-event action-co)
  (make-cognitive-event 'ActionRequested action-co #:origin 'LLM))

(define (make-action-completed-event result-co)
  (make-cognitive-event 'ActionCompleted result-co #:origin 'REPL))

(define (make-action-failed-event err-co)
  (make-cognitive-event 'ActionFailed err-co #:origin 'REPL))

(define (make-conflict-detected-event conflict-co)
  (make-cognitive-event 'ConflictDetected conflict-co #:origin 'CONTROL))

(define (make-reflection-raised-event reflection-co)
  (make-cognitive-event 'ReflectionRaised reflection-co #:origin 'METACOGNITION))


;; Cognitive Bus Implementation
(define-record-type <cognitive-bus>
  (%make-bus subscribers-ref history-ref)
  cognitive-bus?
  (subscribers-ref bus-subscribers-cell)
  (history-ref bus-history-cell))

(define (make-cognitive-bus)
  "Creates a new Cognitive Bus instance."
  (%make-bus (list '()) (list '())))

(define (bus-subscribers bus)
  (car (bus-subscribers-cell bus)))

(define (bus-history bus)
  (car (bus-history-cell bus)))

(define (bus-subscribe bus filter-proc handler-proc)
  "Registers a subscriber on the bus. FILTER-PROC can be a symbol (matching event-type) or a predicate procedure."
  (let* ((filter (if (symbol? filter-proc)
                     (lambda (evt) (eq? (event-type evt) filter-proc))
                     filter-proc))
         (sub (cons filter handler-proc))
         (cell (bus-subscribers-cell bus)))
    (set-car! cell (cons sub (car cell)))
    sub))

(define (bus-publish bus event-or-co)
  "Publishes a Cognitive Event or Cognitive Object to all matching subscribers on the bus."
  (let* ((event (if (cognitive-event? event-or-co)
                    event-or-co
                    (make-cognitive-event 'WorkspaceBroadcast event-or-co)))
         (cell (bus-history-cell bus)))
    ;; Record in history
    (set-car! cell (cons event (car cell)))
    ;; Notify matching subscribers
    (for-each (lambda (sub)
                (let ((filter (car sub))
                      (handler (cdr sub)))
                  (when (catch #t (lambda () (filter event)) (lambda _ #f))
                    (catch #t (lambda () (handler event)) (lambda (k . args) #f)))))
              (bus-subscribers bus))
    event))

(define (bus-retract bus co-id)
  "Publishes a RetractCO semantic event indicating an object has been withdrawn."
  (let ((evt (make-cognitive-event 'CO_Retracted co-id #:origin 'CONTROL)))
    (bus-publish bus evt)))

(define (bus-supersede bus old-co-id new-co)
  "Publishes a SupersedeCO semantic event indicating OLD-CO-ID is replaced by NEW-CO."
  (let ((evt (make-cognitive-event 'CO_Superseded `(("old-id" . ,old-co-id) ("new-co" . ,new-co)) #:origin 'CONTROL)))
    (bus-publish bus evt)))

(define (bus-events-history bus)
  (reverse (bus-history bus)))
