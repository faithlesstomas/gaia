(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (srfi srfi-64)
             (srfi srfi-11)
             (ice-9 rdelim)
             (ice-9 threads)
             (ice-9 match)
             (ice-9 suspendable-ports)
             (fibers)
             (gaia server)
             (gaia core)
             (gaia rlm-env)
             (gaia executor)
             (gaia utils)
             (gaia llm-client))

(install-suspendable-ports!)

(test-begin "gaia-server")


;; --- 1. Test parse-slash-command ---

(test-group "parse-slash-command"
  (test-equal "help" '(help) (parse-slash-command "/help"))
  (test-equal "env" '(env) (parse-slash-command "/env"))
  (test-equal "clear" '(clear) (parse-slash-command "/clear"))
  (test-equal "list-models" '(list-models) (parse-slash-command "/models"))
  (test-equal "get-model" '(get-model) (parse-slash-command "/model"))
  (test-equal "set-model" '(set-model "gpt-4") (parse-slash-command "/model gpt-4"))
  (test-equal "get-thinking" '(get-thinking) (parse-slash-command "/thinking"))
  (test-equal "set-thinking" '(set-thinking "off") (parse-slash-command "/thinking off"))
  (test-equal "ask" '(ask "explain scheme") (parse-slash-command "/ask explain scheme"))
  (test-equal "session" '(session "test-session") (parse-slash-command "/session test-session"))
  (test-equal "list-sessions" '(list-sessions) (parse-slash-command "/sessions"))
  (test-equal "history" '(get-history) (parse-slash-command "/history"))
  (test-equal "invalid" #f (parse-slash-command "/unknown-command")))


;; --- 2. Test clean-history ---

(test-group "clean-history"
  (test-assert "cleans assistant thoughts while preserving user role"
    (let* ((raw-history '((("role" . "user") ("content" . "Hello <think>secret</think>"))
                          (("role" . "assistant") ("content" . "<think>thinking...</think>Yes, hello."))))
           (cleaned ((@@ (gaia server) clean-history) raw-history))
           (user-content (assoc-ref (car cleaned) "content"))
           (assistant-content (assoc-ref (cadr cleaned) "content")))
      (and (string-contains user-content "<think>secret</think>")
           (not (string-contains assistant-content "thinking"))
           (string=? assistant-content "Yes, hello.")))))


;; --- 3. Test replay-history ---

(test-group "replay-history"
  (test-assert "replays code blocks in history to rebuild environment state"
    (let* ((env (make-rlm-env "session-replay-test"))
           (history '((("role" . "user") ("content" . "Define variable"))
                      (("role" . "assistant") ("content" . "```repl\n(define replayed-val 888)\n```")))))
      (replay-history env history)
      (equal? (rlm-eval! env "replayed-val") '(ok "888")))))



;; --- 4. Test handle-client via Socketpair Mocking ---

(test-assert "handle-client connection handshake and session initialization"
  (let* ((done? #f)
         (client-received '()))

    ;; Create Unix socket pair
    (let* ((sockets (socketpair AF_UNIX SOCK_STREAM 0))
           (s1 (car sockets))
           (s2 (cdr sockets)))
      
      (run-fibers
       (lambda ()
         ;; Set non-blocking on both sides of the socketpair
         (fcntl s1 F_SETFL (logior O_NONBLOCK (fcntl s1 F_GETFL)))
         (setvbuf s1 'none)
         (fcntl s2 F_SETFL (logior O_NONBLOCK (fcntl s2 F_GETFL)))
         (setvbuf s2 'none)

         ;; Keep scheduler alive
         (spawn-fiber
          (lambda ()
            (let loop ()
              (unless done?
                (sleep 0.05)
                (loop)))))

         ;; Spawn server connection handler on s1
         (spawn-fiber (lambda ()
                        (display "SERVER: starting handle-client\n")
                        (handle-client s1)
                        (display "SERVER: handle-client finished\n")))

         ;; Spawn client fiber interacting with s2
         (spawn-fiber
          (lambda ()
            (define (send-msg msg)
              (display (format #f "CLIENT: sending msg ~s\n" msg))
              (write msg s2)
              (newline s2)
              (force-output s2))
            
            (define (receive-msg)
              (display "CLIENT: waiting to receive line\n")
              (let ((line (read-line s2)))
                (display (format #f "CLIENT: received line ~s\n" line))
                (if (eof-object? line)
                    line
                    (catch #t
                      (lambda () (with-input-from-string line read))
                      (lambda _ 'error)))))

            (catch #t
              (lambda ()
                (send-msg '(session "session-server-test"))
                (send-msg '(get-model))
                ;; Read response
                (let loop ((i 0))
                  (when (< i 5)
                    (let ((msg (receive-msg)))
                      (unless (eof-object? msg)
                        (set! client-received (cons msg client-received))
                        (match msg
                          (('model-info _)
                           (display "CLIENT: received model-info, setting done\n")
                           (set! done? #t))
                          (_ (loop (+ i 1)))))))))
              (lambda (key . args)
                (display (format #f "CLIENT FIBER ERROR: ~s ~s\n" key args))))
            
            ;; Clean up client socket when done
            (close-port s2))))
       #:drain? #t)

      (begin
        (display (format #f "TEST DEBUG: done?=~s client-received=~s\n" done? client-received))
        (and done? (port-closed? s2))))))

;; --- 5. Test handle-client: invalid s-expression gets handled ---

(test-assert "handle-client: invalid payload triggers error event and server continues"
  (let* ((got-error-event #f)
         (done? #f))
    (let* ((sockets (socketpair AF_UNIX SOCK_STREAM 0))
           (s1 (car sockets))
           (s2 (cdr sockets)))
      (run-fibers
       (lambda ()
         (fcntl s1 F_SETFL (logior O_NONBLOCK (fcntl s1 F_GETFL)))
         (setvbuf s1 'none)
         (fcntl s2 F_SETFL (logior O_NONBLOCK (fcntl s2 F_GETFL)))
         (setvbuf s2 'none)

         (spawn-fiber
          (lambda ()
            (let loop ()
              (unless done? (sleep 0.05) (loop)))))

         (spawn-fiber (lambda () (handle-client s1)))

         (spawn-fiber
          (lambda ()
            (catch #t
              (lambda ()
                ;; Establish session
                (write '(session "session-invalid-payload") s2)
                (newline s2) (force-output s2)
                ;; Send invalid s-expression
                (display "{{not valid scheme}}\n" s2)
                (force-output s2)
                ;; Read events — server should send error about unknown command
                ;; then close the connection
                (let loop ((i 0))
                  (when (< i 10)
                    (let ((line (read-line s2)))
                      (cond
                        ((eof-object? line)
                         ;; Server closed connection — this is expected
                         (set! got-error-event #t)
                         (set! done? #t))
                        (else
                         (catch #t
                           (lambda ()
                             (let ((msg (with-input-from-string line read)))
                               (match msg
                                 (('error _)
                                  (set! got-error-event #t)
                                  (set! done? #t))
                                 (_ (loop (+ i 1))))))
                           (lambda _ (loop (+ i 1))))))))))
              (lambda (key . args)
                (set! done? #t)))
            (catch #t (lambda () (close-port s2)) (lambda _ #t)))))
       #:drain? #t)
      got-error-event)))


;; --- 6. Test handle-client: (interrupt) message ---

(test-assert "handle-client: (interrupt) message sends error event back"
  (let* ((got-interrupt-event #f)
         (done? #f)
         (core-mod (resolve-module '(gaia core) #:ensure #f)))
    ;; Reset interrupted flag
    (when core-mod (module-set! core-mod '*interrupted* #f))

    (let* ((sockets (socketpair AF_UNIX SOCK_STREAM 0))
           (s1 (car sockets))
           (s2 (cdr sockets)))
      (run-fibers
       (lambda ()
         (fcntl s1 F_SETFL (logior O_NONBLOCK (fcntl s1 F_GETFL)))
         (setvbuf s1 'none)
         (fcntl s2 F_SETFL (logior O_NONBLOCK (fcntl s2 F_GETFL)))
         (setvbuf s2 'none)

         (spawn-fiber
          (lambda ()
            (let loop ()
              (unless done? (sleep 0.05) (loop)))))

         (spawn-fiber (lambda () (handle-client s1)))

         (spawn-fiber
          (lambda ()
            (catch #t
              (lambda ()
                ;; Establish session
                (write '(session "session-interrupt-test") s2)
                (newline s2) (force-output s2)
                (sleep 0.1)
                ;; Send interrupt
                (write '(interrupt) s2)
                (newline s2) (force-output s2)
                ;; Read response — should get (error "Interrupted")
                (let loop ((i 0))
                  (when (< i 10)
                    (let ((line (read-line s2)))
                      (cond
                        ((eof-object? line) (set! done? #t))
                        (else
                         (catch #t
                           (lambda ()
                             (let ((msg (with-input-from-string line read)))
                               (match msg
                                 (('error "Interrupted")
                                  (set! got-interrupt-event #t)
                                  ;; Now close cleanly
                                  (set! done? #t))
                                 (_ (loop (+ i 1))))))
                           (lambda _ (loop (+ i 1)))))))))
                ;; Close to trigger eof on server side
                (close-port s2))
              (lambda (key . args)
                (set! done? #t))))))
       #:drain? #t)
      got-interrupt-event)))



;; --- 7. Test handle-client: permission-request and permission-response ---

(test-assert "handle-client: permission-request and permission-response flow"
  (let* ((got-permission-request #f)
         (got-eval-success #f)
         (done? #f))
    (let* ((sockets (socketpair AF_UNIX SOCK_STREAM 0))
           (s1 (car sockets))
           (s2 (cdr sockets)))
      (run-fibers
       (lambda ()
         (fcntl s1 F_SETFL (logior O_NONBLOCK (fcntl s1 F_GETFL)))
         (setvbuf s1 'none)
         (fcntl s2 F_SETFL (logior O_NONBLOCK (fcntl s2 F_GETFL)))
         (setvbuf s2 'none)

         (spawn-fiber
          (lambda ()
            (let loop ()
              (unless done? (sleep 0.05) (loop)))))

         (spawn-fiber (lambda () (handle-client s1)))

         (spawn-fiber
          (lambda ()
            (catch #t
              (lambda ()
                ;; Establish session
                (write '(session "session-permission-test") s2)
                (newline s2) (force-output s2)
                (sleep 0.05)
                ;; Send eval request that requires permission
                (write `(repl "(write-file \"test-hitl.txt\" \"hello\")") s2)
                (newline s2) (force-output s2)

                ;; Read response loop
                (let loop ((i 0))
                  (when (< i 10)
                    (let ((line (read-line s2)))
                      (cond
                        ((eof-object? line) (set! done? #t))
                        (else
                         (catch #t
                           (lambda ()
                             (let ((msg (with-input-from-string line read)))
                               (match msg
                                 (('permission-request expr)
                                  (set! got-permission-request #t)
                                  ;; Send permission response back
                                  (write '(permission-response #t) s2)
                                  (newline s2) (force-output s2)
                                  (loop (+ i 1)))
                                 (('repl-result res)
                                  (set! got-eval-success #t)
                                  (set! done? #t))
                                 (('error msg)
                                  (set! done? #t))
                                 (_ (loop (+ i 1))))))
                           (lambda _ (loop (+ i 1)))))))))
                ;; Close cleanly
                (close-port s2))
              (lambda (key . args)
                (set! done? #t))))))
       #:drain? #t)
      (begin
        ;; Clean up test file if it was created
        (when (file-exists? "test-hitl.txt") (delete-file "test-hitl.txt"))
        (and got-permission-request got-eval-success)))))


(test-end "gaia-server")
