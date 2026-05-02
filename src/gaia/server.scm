(define-module (gaia server)
  #:use-module (fibers)
  #:use-module (fibers channels)
  #:use-module (ice-9 match)
  #:use-module (ice-9 threads)
  #:use-module (gaia core)
  #:use-module (gaia rlm-env)
  #:use-module (gaia config)
  #:use-module (gaia llm-client)
  #:use-module (gaia utils)
  #:export (start-server))

(define (send-event client-socket event)
  "Write an S-expression event to client, flushing immediately."
  (write event client-socket)
  (newline client-socket)
  (force-output client-socket))

(define (handle-client client-socket)
  "Handles communication with a single CLI client.
Maintains persistent REPL environment and conversation history."
  (let loop ((env (make-rlm-env))
             (history '())
             (session-id (string-append "gaia-"
                                        (number->string (current-time))
                                        "-"
                                        (number->string (random 10000)))))
    (match (read client-socket)
      ((? eof-object?)
       (close-port client-socket))

      ;; Standard RLM evaluation (sends task to AI agent loop)
      (('eval task)
       (let ((event-sink (lambda (event) (send-event client-socket event))))
         (catch #t
           (lambda ()
             (let ((result (rlm-loop session-id task 0 history env
                                     #:event-handler event-sink)))
               (loop env
                     (append history
                             (list `(("role" . "user") ("content" . ,task))
                                   `(("role" . "assistant") ("content" . ,result))))
                     session-id)))
           (lambda (key . args)
             (let ((msg (format #f "Engine Error (~a): ~a" key args)))
               (send-event client-socket `(error ,msg))
               (loop env history session-id))))))

      ;; Direct REPL code execution (/eval in CLI)
      (('repl code)
       (catch #t
         (lambda ()
           (match (rlm-eval! env code)
             (('ok result)
              (send-event client-socket `(result ,result)))
             (('error type msg)
              (send-event client-socket
                          `(error ,(format #f "~a: ~a" type msg))))))
         (lambda (key . args)
           (send-event client-socket
                       `(error ,(format #f "~a: ~a" key args)))))
       (loop env history session-id))

      ;; Show REPL environment bindings
      (('env)
       (let ((bindings (rlm-env-user-bindings env)))
         (send-event client-socket `(env-list ,bindings)))
       (loop env history session-id))

      ;; Clear history and environment
      (('clear)
       (send-event client-socket '(info "History and environment cleared."))
       (loop (make-rlm-env) '() session-id))

      ;; Query current model
      (('get-model)
       (send-event client-socket
                   `(model-info ,(get-config 'model)))
       (loop env history session-id))

      ;; Change model
      (('set-model new-model)
       (set-config! 'model new-model)
       (send-event client-socket
                   `(info ,(string-append "Model switched to: " new-model)))
       (loop env history session-id))

      ;; One-shot question (no RLM loop)
      (('ask query)
       (catch #t
         (lambda ()
           (let* ((response (chat-with-llm session-id query
                                           (get-config 'model)
                                           "You are a helpful Guile Scheme expert."
                                           #:history history))
                  (payload (assoc-ref response "payload"))
                  (content (if payload
                               (assoc-ref payload "content")
                               "Error: No payload in response")))
             (send-event client-socket `(final ,content))
             (loop env
                   (append history
                           (list `(("role" . "user") ("content" . ,query))
                                 `(("role" . "assistant") ("content" . ,content))))
                   session-id)))
         (lambda (key . args)
           (send-event client-socket
                       `(error ,(format #f "Ask Error (~a): ~a" key args)))
           (loop env history session-id))))

      (else
       (send-event client-socket '(error "Unknown command"))
       (loop env history session-id)))))

(define (start-server path)
  "Starts the GAIA Headless Engine on a UNIX socket."
  (load-config)
  (display (format #f "[GAIA] Config loaded. Model: ~a\n" (get-config 'model)))
  (when (file-exists? path) (delete-file path))
  (let ((server-socket (socket AF_UNIX SOCK_STREAM 0))
        (addr (make-socket-address AF_UNIX path)))
    (fcntl server-socket F_SETFL (logior (fcntl server-socket F_GETFL) O_NONBLOCK))
    (bind server-socket addr)
    (listen server-socket 128)
    (display (string-append "[GAIA] Server listening on " path "\n"))

    (run-fibers
     (lambda ()
       (let loop ()
         (match (accept server-socket)
           ((client-socket . client-addr)
            (display "[GAIA] Client connected.\n")
            (fcntl client-socket F_SETFL (logior (fcntl client-socket F_GETFL) O_NONBLOCK))
            (spawn-fiber (lambda () (handle-client client-socket)))
            (loop))))))))
