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
            ncsi-simulate-stream!))

(define-record-type <ncsi-client-adapter>
  (%make-adapter session active-requests-cell on-error)
  ncsi-client-adapter?
  (session adapter-session)
  (active-requests-cell adapter-active-requests-cell)
  (on-error adapter-on-error))

(define* (make-ncsi-client-adapter session #:key (on-error #f))
  (unless (cognitive-session? session)
    (error "make-ncsi-client-adapter requires a <cognitive-session>" session))
  (%make-adapter session (list '()) (or on-error (lambda (err) #f))))

(define (ncsi-dispatch-event! adapter event-or-alist)
  "Parse and publish an incoming NCSI wire event to the session's Cognitive Bus."
  (let* ((session (adapter-session adapter))
         (bus (session-bus session)))
    (catch #t
      (lambda ()
        (let ((ncsi-evt (if (ncsi-event? event-or-alist)
                            event-or-alist
                            (parse-ncsi-event event-or-alist))))
          (case (ncsi-event-type ncsi-evt)
            ((NeuralStateObserved)
             (bus-publish bus (make-cognitive-event
                               'NeuralStateObserved
                               (ncsi-event-payload ncsi-evt)
                               #:origin 'NEURAL_J_LENS)))
            ((TokenDelta)
             (bus-publish bus (make-cognitive-event
                               'TokenDelta
                               (ncsi-event-payload ncsi-evt)
                               #:origin 'NEURAL_SIDE_CAR)))
            ((GenerationStarted)
             (bus-publish bus (make-cognitive-event
                               'GenerationStarted
                               (ncsi-event-payload ncsi-evt)
                               #:origin 'NEURAL_SIDE_CAR)))
            ((GenerationCompleted)
             (bus-publish bus (make-cognitive-event
                               'GenerationCompleted
                               (ncsi-event-payload ncsi-evt)
                               #:origin 'NEURAL_SIDE_CAR)))
            ((GenerationFailed)
             (session-emit! session 'NCSI_GenerationFailed
                            (ncsi-event-payload ncsi-evt)
                            #:origin 'NEURAL_SIDE_CAR))
            (else #f))
          ncsi-evt))
      (lambda (key . args)
        (session-emit! session 'ProcessorFailed
                       `((component . ncsi-adapter)
                         (error-key . ,key)
                         (details . ,(format #f "~s" args)))
                       #:origin 'CONTROL)
        ((adapter-on-error adapter) (cons key args))
        #f))))

(define (ncsi-simulate-stream! adapter events)
  "Sequentially dispatch a list of NCSI events to simulate streaming from sidecar."
  (map (lambda (evt) (ncsi-dispatch-event! adapter evt)) events))
