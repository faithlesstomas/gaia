(define-module (test-meta-commands)
  #:use-module (srfi srfi-64)
  #:use-module (gaia server)
  #:use-module (gaia rlm-env)
  #:use-module (gaia core)
  #:use-module (ice-9 match)
  #:use-module (ice-9 threads)
  #:use-module (ice-9 rdelim))

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
              '("meta-test-1" "meta-test-2" "meta-test-3"))

    (let ((server-thread (call-with-new-thread
                          (lambda ()
                            (catch #t
                              (lambda ()
                                ((@@ (gaia server) handle-client) server-port))
                              (lambda (key . args)
                                #f)))))) ;; Silence expected read errors on close
      
      (define (send msg)
        (write msg client-port)
        (newline client-port)
        (force-output client-port))

      (define (receive)
        (read client-port))

      (dynamic-wind
        (lambda () #t)
        (lambda () (proc send receive))
        (lambda ()
          (usleep 100000) ;; Give server 100ms to settle
          (close-port client-port))))))

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
       (send '(env))
       (let ((res (receive)))
         (match res
           (('env-list '()) #t)
           (_ #f))))))

  (test-assert "/model returns current model"
    (with-test-client
     (lambda (send receive)
       (send '(session "meta-test-3"))
       (send '(get-model))
       (let ((res (receive)))
         (match res
           (('model-info _) #t)
           (_ #f)))))))

(test-end "gaia-meta-commands")

(exit 0)
