(define-module (test-meta-commands)
  #:use-module (srfi srfi-64)
  #:use-module (gaia server)
  #:use-module (gaia rlm-env)
  #:use-module (gaia core)
  #:use-module (ice-9 match)
  #:use-module (ice-9 threads)
  #:use-module (ice-9 rdelim)
  #:use-module (fibers))

(sigaction SIGPIPE SIG_IGN)

(test-begin "gaia-meta-commands")

;; Helper to simulate a client session
(define (with-test-client proc)
  (let* ((ports (socketpair AF_UNIX SOCK_STREAM 0))
         (server-port (car ports))
         (client-port (cdr ports)))
    
    ;; Cleanup existing test sessions
    (for-each (lambda (id)
                (let ((path (string-append "sessions/" id ".json")))
                  (when (file-exists? path) (delete-file path))))
              '("meta-test-1" "meta-test-2" "meta-test-3" "meta-test-4"))

    (let ((server-thread (call-with-new-thread
                          (lambda ()
                            (dynamic-wind
                              (lambda () #t)
                              (lambda ()
                                (catch #t
                                  (lambda ()
                                    (run-fibers
                                     (lambda ()
                                       ((@@ (gaia server) handle-client) server-port))
                                     #:drain? #t))
                                  (lambda (key . args)
                                    #f)))
                              (lambda ()
                                (close-port server-port))))))) ;; Silence expected read errors on close
      
      (define (send msg)
        (write msg client-port)
        (newline client-port)
        (force-output client-port))

      (define (receive)
        "Read next non-info event from server (skipping info acks) with a 30s timeout."
        (let loop ()
          (let ((res (select (list client-port) '() '() 30)))
            (if (null? (car res))
                (throw 'timeout-error "Receive timed out after 30 seconds")
                (let ((msg (read client-port)))
                  (match msg
                    (('info . _) (loop))
                    (('stream-log . _) (loop))
                    (_ msg)))))))

      (dynamic-wind
        (lambda () #t)
        (lambda () (proc send receive))
        (lambda ()
          (usleep 100000) ;; Give server 100ms to settle
          (close-port client-port)
          (join-thread server-thread))))))

(test-group "Meta-Command Protocol"
  
  (test-assert "/env returns user bindings"
    (with-test-client
     (lambda (send receive)
       (send '(session "meta-test-1"))
       (send '(repl "(define test-meta-var 999)"))
       (receive) ;; Skip result
       (send '(env))
       (let ((res (receive)))
         (match res
           (('env-list bindings)
            (let ((pair (assoc 'test-meta-var bindings)))
              (and pair (equal? (cdr pair) "999"))))
           (_ #f))))))

  (test-assert "/clear resets the session"
    (with-test-client
     (lambda (send receive)
       (send '(session "meta-test-2"))
       (send '(repl "(define should-disappear 1)"))
       (receive)
       (send '(clear))
       (receive) ;; Consume the (final ...) event
       (send '(env))
       (let ((res (receive)))
         (match res
           (('env-list '()) #t)
           (_ (begin (display (format #f "[DEBUG] Received res: ~s\n" res)) #f)))))))

   (test-assert "/model returns current model"
    (with-test-client
     (lambda (send receive)
       (send '(session "meta-test-3"))
       (send '(get-model))
       (let ((res (receive)))
         (match res
           (('model-info _) #t)
           (_ #f))))))

  (test-assert "/help returns help text"
    (with-test-client
     (lambda (send receive)
       (send '(session "meta-test-4"))
       (send '(help))
       (let ((res (receive)))
         (match res
           (('final help-text)
            (and (string? help-text)
                 (string-prefix? "Available Commands:" help-text)))
           (_ #f)))))))

(let* ((runner (test-runner-current))
       (fail (if runner (test-runner-fail-count runner) 0)))
  (test-end "gaia-meta-commands")
  (exit (if (> fail 0) 1 0)))
