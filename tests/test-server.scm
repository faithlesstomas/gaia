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

(test-end "gaia-server")
