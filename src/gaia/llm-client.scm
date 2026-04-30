(define-module (gaia llm-client)
  #:use-module (web client)
  #:use-module (web response)
  #:use-module (web uri)
  #:use-module (rnrs bytevectors)
  #:use-module (ice-9 receive)
  #:use-module (ice-9 optargs)
  #:use-module (ice-9 threads)
  #:use-module (gaia utils)
  #:use-module (gaia config)
  #:export (chat-with-llm get-models))

;; Shared interrupt flag — set by signal handler in core.scm
;; We import it by reference so both modules see the same value.
(define (interrupted?)
  (module-ref (resolve-module '(gaia core)) '*interrupted*))

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

(define* (chat-with-llm session-id input model system-prompt #:key (think #f) (history '()))
  (let* ((host (get-config 'llm-url))
         (url (string-append host "/v1/chat/completions"))
         (messages-list (append (list `(("role" . "system") ("content" . ,system-prompt)))
                                history
                                (list `(("role" . "user") ("content" . ,input)))))
         (body (scm->json `(("model" . ,model)
                            ("messages" . ,(list->vector messages-list))
                            ("think" . ,think)
                            ("stream" . #f))))
         (headers '((content-type . (application/json)))))
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
              json-response))))))

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
