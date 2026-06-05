(define-module (gaia llm-client)
  #:use-module (web client)
  #:use-module (web response)
  #:use-module (web uri)
  #:use-module (rnrs bytevectors)
  #:use-module (ice-9 receive)
  #:use-module (ice-9 optargs)
  #:use-module (ice-9 match)
  #:use-module (ice-9 threads)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (gaia utils)
  #:use-module (gaia config)
  #:export (chat-with-llm get-models abort-active-llm-calls! make-stream-filter))


;; Shared interrupt flag — set by signal handler in core.scm
;; We import it by reference so both modules see the same value.
(define (interrupted?)
  (module-ref (resolve-module '(gaia core)) '*interrupted*))

(define *active-llm-port* #f)

(define (abort-active-llm-calls!)
  (let ((port *active-llm-port*))
    (when (and port (not (port-closed? port)))
      (catch #t
        (lambda () (close-port port))
        (lambda _ #f))
      (set! *active-llm-port* #f))))

(define (set-nonblocking! port)
  (fcntl port F_SETFL (logior O_NONBLOCK (fcntl port F_GETFL)))
  (setvbuf port 'none))

(define (interruptible-http-post url body headers)
  "Runs http-post in a thread so the main thread can poll for Ctrl-C.
Returns (response-header . response-body) or throws 'user-interrupt."
  (let* ((result-box (make-mutex))
         (result-val #f)
         (result-err #f)
         (done? #f)
         (worker (call-with-new-thread
                  (lambda ()
                    (catch #t
                      (lambda ()
                        (receive (hdr body)
                            (http-post url #:body body #:headers headers)
                          (set! result-val (cons hdr body))))
                      (lambda (key . args)
                        (set! result-err (cons key args))))
                    (set! done? #t)))))
    ;; Poll loop: check every 100ms if worker is done or if interrupted
    (let poll ()
      (cond
       ((interrupted?)
        ;; User pressed Ctrl+C — cancel thread and bail out
        (cancel-thread worker)
        (throw 'user-interrupt))
       (done?
        ;; Worker finished — return result or re-throw error
        (if result-err
            (apply throw (car result-err) (cdr result-err))
            result-val))
       (else
        (usleep 100000) ;; 100ms
        (poll))))))

(define (check-interrupt!)
  (when (interrupted?)
    (throw 'user-interrupt)))

(define (make-stream-filter stream-callback)
  (let ((thinking? #f)
        (buffer "")
        (start-tags '("<think>" "<|think|>"))
        (end-tags '("</think>" "</|think|>")))

    (define (longest-prefix-suffix str targets)
      (let ((len (string-length str)))
        (let loop ((l len))
          (if (zero? l)
              0
              (let ((suffix (substring str (- len l))))
                (if (any (lambda (tgt) (string-prefix? suffix tgt)) targets)
                    l
                    (loop (- l 1))))))))

    (define (find-first-tag str targets)
      (let loop ((targets targets)
                 (best #f))
        (if (null? targets)
            best
            (let* ((tgt (car targets))
                   (idx (string-contains str tgt)))
              (if idx
                  (if (or (not best) (< idx (car best)))
                      (loop (cdr targets) (list idx (string-length tgt) tgt))
                      (loop (cdr targets) best))
                  (loop (cdr targets) best))))))

    (define (process-buffer!)
      (let* ((targets (if thinking? end-tags start-tags))
             (found (find-first-tag buffer targets)))
        (if found
            (let* ((idx (car found))
                   (len (cadr found))
                   (tag (caddr found))
                   (pre (substring buffer 0 idx)))
              (when (> (string-length pre) 0)
                (stream-callback (list (if thinking? 'thought 'token) pre)))
              (set! buffer (substring buffer (+ idx len)))
              (set! thinking? (not thinking?))
              (process-buffer!))
            (let ((l (longest-prefix-suffix buffer targets)))
              (if (> l 0)
                  (let ((safe-len (- (string-length buffer) l)))
                    (when (> safe-len 0)
                      (let ((safe-str (substring buffer 0 safe-len)))
                        (stream-callback (list (if thinking? 'thought 'token) safe-str)))
                      (set! buffer (substring buffer safe-len))))
                  (begin
                    (when (> (string-length buffer) 0)
                      (stream-callback (list (if thinking? 'thought 'token) buffer)))
                    (set! buffer "")))))))

    (lambda (event)
      (match event
        (('token text)
         (set! buffer (string-append buffer text))
         (process-buffer!))
        (('thought text)
         (stream-callback event))
        (('flush)
         (when (> (string-length buffer) 0)
           (stream-callback (list (if thinking? 'thought 'token) buffer))
           (set! buffer "")))
        (_
         (when (and (> (string-length buffer) 0)
                    (not (string-prefix? "data:" (format #f "~a" event))))
           (stream-callback (list (if thinking? 'thought 'token) buffer))
           (set! buffer ""))
         (stream-callback event))))))

(define* (chat-with-llm session-id input model system-prompt #:key (think #f) (history '()) (stream-callback #f))
  (let* ((host (get-config 'llm-url))
         (url (string-append host "/v1/chat/completions"))
         (messages-list (append (list `(("role" . "system") ("content" . ,system-prompt)))
                                history
                                (list `(("role" . "user") ("content" . ,input)))))
         (body (scm->json `(("model" . ,model)
                            ("messages" . ,(list->vector messages-list))
                            ("think" . ,think)
                            ("stream" . ,(if stream-callback #t #f)))))
         (headers '((content-type . (application/json)))))
    (if stream-callback
        ;; Asynchronous Streaming Path
        (let ((s (open-socket-for-uri (string->uri url))))
          (set-nonblocking! s)
          (receive (response response-port)
              (http-request url #:method 'POST #:body body #:headers headers #:streaming? #t #:port s)
            (let ((status (response-code response)))
              (if (not (= status 200))
                  (let ((err-body (read-string response-port)))
                    (close-port response-port)
                    `(("error" . ,err-body)))
                  (dynamic-wind
                    (lambda () (set! *active-llm-port* response-port))
                    (lambda ()
                      (let* ((accumulated-content '())
                             (accumulated-reasoning '())
                             (filtered-callback (make-stream-filter
                                                 (lambda (evt)
                                                   (match evt
                                                     (('token text)
                                                      (set! accumulated-content (cons text accumulated-content))
                                                      (when stream-callback (stream-callback evt)))
                                                     (('thought text)
                                                      (set! accumulated-reasoning (cons text accumulated-reasoning))
                                                      (when stream-callback (stream-callback evt)))
                                                     (_
                                                      (when stream-callback (stream-callback evt))))))))
                        (let loop ()
                          (check-interrupt!)
                          (let ((line (read-line response-port)))
                            (cond
                             ((or (eof-object? line) (string-prefix? "data: [DONE]" line))
                              (filtered-callback '(flush))
                              (close-port response-port)
                              `(("payload" . (("content" . ,(string-join (reverse accumulated-content) ""))
                                              ("reasoning" . ,(string-join (reverse accumulated-reasoning) ""))))))
                             ((string-prefix? "data: " line)
                              (let* ((json-str (string-trim-both (substring line 6)))
                                     (json-scm (catch #t
                                                 (lambda () (json->scm json-str))
                                                 (lambda _ #f))))
                                (if json-scm
                                    (let* ((choices (assoc-ref json-scm "choices"))
                                           (first-choice (and choices (> (vector-length choices) 0) (vector-ref choices 0)))
                                           (delta (and first-choice (assoc-ref first-choice "delta")))
                                           (content (and delta (assoc-ref delta "content")))
                                           (reasoning (and delta (assoc-ref delta "reasoning_content"))))
                                      (when (and content (> (string-length content) 0))
                                        (filtered-callback `(token ,content)))
                                      (when (and reasoning (> (string-length reasoning) 0))
                                        (filtered-callback `(thought ,reasoning)))
                                      (loop))
                                    (loop))))
                             (else
                              (loop)))))))
                    (lambda () (set! *active-llm-port* #f)))))))
        ;; Synchronous Non-streaming Path
        (let* ((result (interruptible-http-post url body headers))
               (response-header (car result))
               (response-body (cdr result)))
          (let* ((body-str (if (string? response-body) response-body (utf8->string response-body)))
                 (json-response (catch #t
                                  (lambda () (json->scm body-str))
                                  (lambda (key . args)
                                    (when (eq? key 'user-interrupt) (apply throw key args))
                                    `(("error" . ,body-str))))))
            ;; OpenAI format translation to GAIA expected format
            (let ((choices (assoc-ref json-response "choices")))
              (if (and choices (> (vector-length choices) 0))
                  (let* ((first-choice (vector-ref choices 0))
                         (message (assoc-ref first-choice "message"))
                         (content (if message (assoc-ref message "content") #f))
                         (reasoning (if message (assoc-ref message "reasoning_content") #f)))
                    (if content
                        `(("payload" . (("content" . ,content)
                                        ("reasoning" . ,(or reasoning "")))))
                        json-response))
                  json-response)))))))

(define (get-models)
  "Fetches the list of available models from OpenAI compatible server."
  (let* ((host (get-config 'llm-url))
         (url (string-append host "/v1/models")))
    (receive (response-header response-body)
        (http-get url)
      (let* ((body-str (if (string? response-body) response-body (utf8->string response-body)))
             (json-response (catch #t
                                   (lambda () (json->scm body-str))
                                   (lambda (key . args)
                                     (when (eq? key 'user-interrupt) (apply throw key args))
                                     `(("error" . ,body-str))))))
        (let ((data (assoc-ref json-response "data")))
          (if (vector? data)
              (map (lambda (m) (assoc-ref m "id")) (vector->list data))
              '()))))))
