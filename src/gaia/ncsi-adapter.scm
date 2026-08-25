(define-module (gaia ncsi-adapter)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (ice-9 match)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia ncsi)
  #:export (<ncsi-client-adapter>
            make-ncsi-client-adapter
            ncsi-client-adapter?
            ncsi-dispatch-event!
            ncsi-simulate-stream!
            ncsi-report-adapter-failure!
            ncsi-record-fallback-required!))

(define-record-type <ncsi-client-adapter>
  (%make-adapter session active-requests-cell on-error)
  ncsi-client-adapter?
  (session adapter-session)
  (active-requests-cell adapter-active-requests-cell)
  (on-error adapter-on-error))

(define* (make-ncsi-client-adapter session #:key (on-error #f))
  (unless (cognitive-session? session)
    (error "make-ncsi-client-adapter requires a <cognitive-session>" session))
  (unless (or (not on-error) (procedure? on-error))
    (error "on-error must be a procedure or #f" on-error))
  (%make-adapter session (list '()) (or on-error (lambda (err) #f))))

(define (adapter-request-state adapter request-id)
  (assoc-ref (car (adapter-active-requests-cell adapter)) request-id))

(define (set-adapter-request-state! adapter request-id state)
  (let ((cell (adapter-active-requests-cell adapter)))
    (set-car! cell
              (acons request-id state
                     (filter (lambda (entry)
                               (not (equal? (car entry) request-id)))
                             (car cell)))))
  state)

(define (next-request-state adapter event)
  "Accept exactly one started-to-terminal lifecycle per NCSI request.
Terminal states are intentionally retained, so duplicate or late wire events
remain rejectable for the lifetime of the adapter."
  (let* ((request-id (ncsi-event-request-id event))
         (type (ncsi-event-type event))
         (state (adapter-request-state adapter request-id)))
    (case type
      ((GenerationStarted)
       (when state
         (error "NCSI_INVALID_LIFECYCLE: request already started or terminated"
                request-id state))
       'ACTIVE)
      ((TokenDelta NeuralStateObserved)
       (unless (eq? state 'ACTIVE)
         (error "NCSI_INVALID_LIFECYCLE: event requires an active request"
                request-id type state))
       'ACTIVE)
      ((GenerationCompleted)
       (unless (eq? state 'ACTIVE)
         (error "NCSI_INVALID_LIFECYCLE: completion requires an active request"
                request-id state))
       'COMPLETED)
      ((GenerationFailed)
       (unless (eq? state 'ACTIVE)
         (error "NCSI_INVALID_LIFECYCLE: failure requires an active request"
                request-id state))
       'FAILED))))

(define (adapter-event-origin event)
  (if (eq? (ncsi-event-type event) 'NeuralStateObserved)
      'NEURAL_J_LENS
      'NEURAL_SIDE_CAR))

(define (ncsi-record-fallback-required! adapter reason)
  (session-emit! (adapter-session adapter) 'NCSI_FallbackRequired
                 `((adapter . ncsi) (reason . ,reason))
                 #:origin 'CONTROL))

(define (record-ncsi-adapter-failure! adapter key args)
  (let ((session (adapter-session adapter))
        (details (format #f "~s" args)))
    ;; Keep the established ProcessorFailed diagnostic for existing Control
    ;; consumers, while exposing typed NCSI failure and explicit fallback need.
    (session-emit! session 'ProcessorFailed
                   `((component . ncsi-adapter)
                     (error-key . ,key)
                     (details . ,details))
                   #:origin 'CONTROL)
    (session-emit! session 'NCSI_AdapterFailed
                   `((error-key . ,key) (details . ,details))
                   #:origin 'NEURAL_SIDE_CAR)
    (ncsi-record-fallback-required! adapter 'invalid-or-unavailable-stream)))

(define (ncsi-report-adapter-failure! adapter key details)
  "Durably expose a transport or protocol failure and request explicit fallback."
  (record-ncsi-adapter-failure! adapter key (list details))
  ((adapter-on-error adapter) (list key details))
  #f)

(define (ncsi-dispatch-event! adapter event-or-alist)
  "Validate, lifecycle-check, durably record, and publish one NCSI event."
  (let ((session (adapter-session adapter)))
    (catch #t
      (lambda ()
        (let ((ncsi-evt (if (ncsi-event? event-or-alist)
                            event-or-alist
                            (parse-ncsi-event event-or-alist))))
          ;; NCSI records supplied by in-process callers must obey the same
          ;; payload rules as wire alists before they can mutate session state.
          (validate-ncsi-event (ncsi-event->alist ncsi-evt))
          (let ((next-state (next-request-state adapter ncsi-evt)))
          ;; Store the transport-independent alist, not an opaque SRFI record,
          ;; so state persistence and later audit/replay remain valid.
            (session-emit! session (ncsi-event-type ncsi-evt)
                           (ncsi-event->alist ncsi-evt)
                           #:origin (adapter-event-origin ncsi-evt))
            ;; Advance the lifecycle only after its corresponding event is
            ;; durable.  A persistence failure therefore cannot manufacture a
            ;; terminal state with no audit record.
            (set-adapter-request-state! adapter (ncsi-event-request-id ncsi-evt)
                                        next-state))
          ncsi-evt))
      (lambda (key . args)
        (record-ncsi-adapter-failure! adapter key args)
        ((adapter-on-error adapter) (cons key args))
        #f))))

(define (ncsi-simulate-stream! adapter events)
  "Sequentially dispatch a list of NCSI events to simulate streaming from sidecar."
  (map (lambda (evt) (ncsi-dispatch-event! adapter evt)) events))
