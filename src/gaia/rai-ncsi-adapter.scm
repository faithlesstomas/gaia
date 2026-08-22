(define-module (gaia rai-ncsi-adapter)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (ice-9 receive)
  #:use-module (ice-9 rdelim)
  #:use-module (web client)
  #:use-module (web response)
  #:use-module (gaia cognitive-processor)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia jspace-processor)
  #:use-module (gaia ncsi)
  #:use-module (gaia ncsi-adapter)
  #:use-module (gaia utils)
  #:export (<rai-ncsi-client>
            make-rai-ncsi-client
            rai-ncsi-client?
            rai-ncsi-generate!
            rai-ncsi-cancel!))

(define VALID-NCSI-MODES '(TEXT_ONLY OBSERVATION_ONLY NCSI_POLICY))

(define-record-type <rai-ncsi-client>
  (%make-rai-client session adapter socket-path token fallback policy-attached-cell)
  rai-ncsi-client?
  (session rai-client-session)
  (adapter rai-client-adapter)
  (socket-path rai-client-socket-path)
  (token rai-client-token)
  (fallback rai-client-fallback)
  (policy-attached-cell rai-client-policy-attached-cell))

(define (default-socket-path)
  (let ((runtime-dir (getenv "XDG_RUNTIME_DIR")))
    (if runtime-dir
        (string-append runtime-dir "/rai/neural.sock")
        "/tmp/rai-neural.sock")))

(define* (make-rai-ncsi-client session
                               #:key
                               (socket-path (default-socket-path))
                               (token (or (getenv "RAI_API_TOKEN") ""))
                               (fallback #f)
                               (on-error #f))
  (unless (cognitive-session? session)
    (error "make-rai-ncsi-client requires a cognitive session" session))
  (unless (and (string? socket-path) (> (string-length socket-path) 0))
    (error "NCSI socket path must be a non-empty string" socket-path))
  (unless (or (not fallback) (procedure? fallback))
    (error "NCSI fallback must be a procedure or #f" fallback))
  (%make-rai-client session
                    (make-ncsi-client-adapter session #:on-error on-error)
                    socket-path token fallback (list #f)))

(define (wire-ref alist key)
  (let ((entry (or (assoc key alist)
                   (assoc (symbol->string key) alist))))
    (and entry (cdr entry))))

(define (open-unix-http-port socket-path)
  (let ((port (socket AF_UNIX SOCK_STREAM 0)))
    (connect port (make-socket-address AF_UNIX socket-path))
    port))

(define (request-headers client)
  (append '((content-type . (application/json)))
          (if (> (string-length (rai-client-token client)) 0)
              `((authorization . ,(string-append "Bearer " (rai-client-token client))))
              '())))

(define (make-request-id)
  (format #f "gaia-ncsi-~a-~a" (current-time) (random 1000000)))

(define (normalize-mode mode)
  (let ((mode (if (string? mode) (string->symbol mode) mode)))
    (unless (memq mode VALID-NCSI-MODES)
      (error "Invalid NCSI execution mode" mode))
    mode))

(define (ensure-policy-processor! client mode base-priority max-proposals)
  (when (and (eq? mode 'NCSI_POLICY)
             (not (car (rai-client-policy-attached-cell client))))
    (attach-processor!
     (rai-client-session client)
     (make-jspace-processor #:base-priority base-priority
                            #:max-proposals max-proposals))
    (set-car! (rai-client-policy-attached-cell client) #t)))

(define (fallback-text value)
  (cond
   ((string? value) value)
   ((list? value)
    (or (wire-ref value 'final-text)
        (let ((payload (wire-ref value 'payload)))
          (and (list? payload) (wire-ref payload 'content)))
        (wire-ref value 'content)))
   (else #f)))

(define (run-fallback client prompt model reason)
  (ncsi-record-fallback-required! (rai-client-adapter client) reason)
  (let ((fallback (rai-client-fallback client)))
    (if fallback
        (let* ((value (fallback prompt model))
               (text (fallback-text value)))
          `((mode . FALLBACK)
            (fallback-reason . ,reason)
            (final-text . ,(or text ""))
            (fallback-value . ,value)))
        `((mode . FAILED)
          (fallback-reason . ,reason)
          (final-text . "")))))

(define* (rai-ncsi-cancel! client request-id)
  "Request cooperative cancellation through the sidecar's UDS API."
  (catch #t
    (lambda ()
      (let* ((port (open-unix-http-port (rai-client-socket-path client)))
             (url (string-append "http://localhost/api/v1/neural/requests/"
                                 request-id "/cancel")))
        (receive (response body)
            (http-request url #:method 'POST
                          #:headers (request-headers client)
                          #:port port)
          (and (= (response-code response) 200) body))))
    (lambda _ #f)))

(define* (rai-ncsi-generate! client prompt model
                             #:key
                             (mode 'OBSERVATION_ONLY)
                             (request-id (make-request-id))
                             (lens-id #f)
                             (max-new-tokens 128)
                             (timeout-seconds 120)
                             (top-k 8)
                             (layers '())
                             (base-priority 1)
                             (max-proposals 64)
                             (on-token #f)
                             (on-observation #f))
  "Run one text-only or read-only-NCSI generation against the RAI UDS sidecar.

The exact NDJSON events are validated and recorded before being exposed to the
session.  NCSI_POLICY attaches the bounded JSPACE processor; OBSERVATION_ONLY
records observations without submitting Workspace proposals.  Any fallback is
explicit in both the durable event trace and the returned result."
  (unless (rai-ncsi-client? client)
    (error "rai-ncsi-generate! requires a RAI NCSI client" client))
  (unless (and (string? prompt) (> (string-length prompt) 0)
               (string? model) (> (string-length model) 0))
    (error "NCSI prompt and model must be non-empty strings" prompt model))
  (unless (or (not on-token) (procedure? on-token))
    (error "on-token must be a procedure or #f" on-token))
  (unless (or (not on-observation) (procedure? on-observation))
    (error "on-observation must be a procedure or #f" on-observation))
  (let* ((mode (normalize-mode mode))
         (effective-lens (and (not (eq? mode 'TEXT_ONLY)) lens-id))
         (body-fields `(("request-id" . ,request-id)
                        ("prompt" . ,prompt)
                        ("model-id" . ,model)
                        ("max-new-tokens" . ,max-new-tokens)
                        ("timeout-seconds" . ,timeout-seconds)
                        ("top-k" . ,top-k)
                        ("layers" . ,(list->vector layers))))
         (body-fields (if effective-lens
                          (acons "lens-id" effective-lens body-fields)
                          body-fields))
         (body (scm->json body-fields))
         (adapter (rai-client-adapter client))
         (final-text "")
         (token-count 0)
         (observation-count 0)
         (failure-reason #f))
    (define (completed-result)
      `((mode . ,mode)
        (request-id . ,request-id)
        (final-text . ,final-text)
        (token-count . ,token-count)
        (observation-count . ,observation-count)
        (fallback . #f)))
    (define (consume-response response-port)
      (let loop ()
        (let ((line (read-line response-port)))
          (cond
           ((eof-object? line)
            (ncsi-report-adapter-failure!
             adapter 'NCSI_TRUNCATED_STREAM
             "sidecar closed without a terminal event")
            (run-fallback client prompt model 'truncated-sidecar-stream))
           ((= (string-length line) 0)
            (loop))
           (else
            (let* ((wire-event (json->scm line))
                   (event (ncsi-dispatch-event! adapter wire-event)))
              (unless event
                (error "NCSI event rejected by GAIA" wire-event))
              (case (ncsi-event-type event)
                ((TokenDelta)
                 (let ((text (wire-ref (ncsi-event-payload event)
                                       'token-text)))
                   (set! token-count (+ token-count 1))
                   (when on-token (on-token text))
                   (loop)))
                ((NeuralStateObserved)
                 (set! observation-count (+ observation-count 1))
                 (when on-observation
                   (on-observation (ncsi-event-payload event)))
                 (loop))
                ((GenerationCompleted)
                 (set! final-text
                       (wire-ref (ncsi-event-payload event) 'final-text))
                 (completed-result))
                ((GenerationFailed)
                 (set! failure-reason
                       (wire-ref (ncsi-event-payload event) 'error-code))
                 (run-fallback client prompt model failure-reason))
                (else (loop)))))))))
    (ensure-policy-processor! client mode base-priority max-proposals)
    (catch #t
      (lambda ()
        (let ((port (open-unix-http-port (rai-client-socket-path client))))
          (receive (response response-port)
              (http-request "http://localhost/api/v1/neural/generate"
                            #:method 'POST
                            #:body body
                            #:headers (request-headers client)
                            #:streaming? #t
                            #:port port)
            (if (not (= (response-code response) 200))
                (let ((details (read-string response-port)))
                  (close-port response-port)
                  (ncsi-report-adapter-failure! adapter 'NCSI_HTTP_ERROR details)
                  (run-fallback client prompt model 'sidecar-http-error))
                (dynamic-wind
                  (lambda () #t)
                  (lambda () (consume-response response-port))
                  (lambda ()
                    (unless (port-closed? response-port)
                      (close-port response-port))))))))
      (lambda (key . args)
        (rai-ncsi-cancel! client request-id)
        (ncsi-report-adapter-failure! adapter key (format #f "~s" args))
        (run-fallback client prompt model 'sidecar-transport-failure)))))
