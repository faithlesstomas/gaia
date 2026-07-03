(define-module (gaia session-orchestrator)
  #:use-module (ice-9 match)
  #:use-module (ice-9 ftw)
  #:use-module (goblins)
  #:use-module (goblins actor-lib methods)
  #:use-module (srfi srfi-11)
  #:use-module (gaia sandbox-actor)
  #:use-module (gaia agent-actor)
  #:use-module (gaia config)
  #:use-module (gaia core)
  #:use-module (gaia executor)
  #:use-module (gaia utils)
  #:export (^session-orchestrator))

(define (clean-history history)
  (map (lambda (turn)
         (let ((role (or (assoc-ref turn 'role) (assoc-ref turn "role")))
               (content (or (assoc-ref turn 'content) (assoc-ref turn "content"))))
           (if (and role (string=? (format #f "~a" role) "assistant") content)
               (map (lambda (pair)
                      (if (member (car pair) '("content" content))
                          (cons (car pair) (clean-assistant-content content))
                          pair))
                    turn)
               turn)))
       history))

(define (new-promise-pair)
  (spawn-promise-and-resolver))

;; Session Orchestrator Actor
(define-actor (^session-orchestrator bcom session-id client-socket channel permission-sink sandbox-actor agent-actor llm-client history)
  #:self self
  (methods
   [(update-history new-history)
    (bcom (^session-orchestrator bcom session-id client-socket channel permission-sink sandbox-actor agent-actor llm-client new-history) 'ok)]

   [(handle-message msg)
    (match msg
      ('eof
       (gaia-log (format #f "[SERVER] Client disconnected (session: ~a)." session-id))
       (close-port client-socket))

      ('interrupt
       ;; Reset interrupted flag
       (let ((core-mod (resolve-module '(gaia core) #:ensure #f)))
         (when core-mod
           (module-set! core-mod '*interrupted* #f)))
       'ok)

      (('eval task)
       (gaia-log (format #f "[SERVER] Received EVAL request: ~a" task))
       (let* ((event-sink (lambda (event) (send-event client-socket event)))
              (chat-promise (<- llm-client 'chat session-id task (get-config 'model)
                                (or (get-config 'system-prompt) SYSTEM_PROMPT)
                                (get-config 'thinking) history event-sink)))
         (on chat-promise
             (lambda (response)
               (let* ((payload (assoc-ref response "payload"))
                      (response-text (if payload
                                         (assoc-ref payload "content")
                                         "Error: No payload in response"))
                      (action-code (extract-code response-text)))
                 (if action-code
                     ;; If the LLM outputted a repl block, enter Task-Solving mode
                     (begin
                       (gaia-log "[SERVER] LLM initiated code execution. Spawning agent-actor solver.")
                       ;; 1. Send the code block event to the client so it gets displayed
                       (send-event client-socket `(code ,action-code))
                       (gaia-log (string-append C-BOLD C-CYAN "\n[GAIA] Executing Scheme Code:\n" C-RESET action-code "\n"))
                       ;; 2. Execute the code in the sandbox
                       (let ((eval-promise (<- sandbox-actor 'eval action-code)))
                         (on eval-promise
                             (lambda (eval-res)
                               (let* ((result-str (match eval-res
                                                    (('ok res)
                                                     (send-event client-socket `(result ,res))
                                                     (gaia-log (string-append C-GREEN "\n[REPL] Success:\n" C-RESET res "\n"))
                                                     (string-append "Code executed successfully. Result:\n" res))
                                                    (('error type msg)
                                                     (let ((err-msg (string-append "Runtime Error (" (symbol->string type) "): " msg)))
                                                       (send-event client-socket `(repl-error err-msg))
                                                       (gaia-log (string-append C-RED "\n[REPL] Runtime Error:\n" C-RESET err-msg "\n"))
                                                       err-msg))))
                                      (step-history (append history
                                                            (list `(("role" . "user") ("content" . ,task))
                                                                  `(("role" . "assistant") ("content" . ,response-text)))))
                                      (step-transcript (list (cons "original-task" task)
                                                             (cons "assistant" (truncate-for-transcript response-text))
                                                             (cons "user" task))))
                                 (let-values (((solve-promise resolve-solve) (new-promise-pair)))
                                   (<- agent-actor 'solve-step task 0 history step-history 2 step-transcript result-str resolve-solve)
                                   (on solve-promise
                                       (lambda (res-pair)
                                         (let ((answer (car res-pair))
                                               (updated-history (cdr res-pair)))
                                           (gaia-log (format #f "[SERVER] EVAL completed. Saving session ~a." session-id))
                                           (save-session session-id updated-history)
                                           (with-output-to-file ".last_session" (lambda () (display session-id)))
                                           (send-event client-socket `(final ,answer))
                                           (<- self 'update-history updated-history)))
                                       #:catch (lambda (err)
                                                 (send-event client-socket `(error ,(format #f "Solver Error: ~a" err))))))))
                             #:catch (lambda (err)
                                       (send-event client-socket `(error ,(format #f "Initial code execution crash: ~a" err)))))))
                     ;; If the LLM did not output a repl block, it's a conversational reply
                     (let* ((prose (clean-assistant-content response-text))
                            (final-sig (extract-final-signal response-text))
                            (final-ans (if final-sig
                                           (match final-sig (('final ans) ans) (('final-var var) var) (_ prose))
                                           prose))
                            (updated-history (append history
                                                     (list `(("role" . "user") ("content" . ,task))
                                                           `(("role" . "assistant") ("content" . ,response-text))))))
                       (gaia-log "[SERVER] LLM responded conversationally.")
                       (send-event client-socket `(final ,final-ans))
                       (save-session session-id updated-history)
                       (with-output-to-file ".last_session" (lambda () (display session-id)))
                       (<- self 'update-history updated-history)))))
             #:catch (lambda (err)
                       (send-event client-socket `(error ,(format #f "LLM request failed: ~a" err)))))))

      (('repl code)
       (gaia-log (format #f "[SERVER] Received REPL code execution request."))
       (let ((eval-promise (<- sandbox-actor 'eval code)))
         (on eval-promise
             (lambda (eval-res)
               (match eval-res
                 (('ok val-str)
                  (gaia-log (format #f "[SERVER] REPL success. Result: ~a" val-str))
                  (let ((updated-history (append history
                                                 (list `(("role" . "assistant")
                                                         ("content" . ,(string-append "```repl\n" code "\n```")))
                                                       `(("role" . "user")
                                                         ("content" . ,(string-append "Result:\n" val-str)))))))
                    (save-session session-id updated-history)
                    (send-event client-socket `(repl-result ,val-str))
                    (<- self 'update-history updated-history)))
                 (('error type msg)
                  (let ((err-msg (format #f "REPL Error (~a): ~a" type msg)))
                    (gaia-log (format #f "[SERVER] REPL error: ~a" err-msg))
                    (send-event client-socket `(error ,err-msg))))))
             #:catch (lambda (err)
                       (let ((err-msg (format #f "REPL Crash: ~a" err)))
                         (gaia-log (format #f "[SERVER] REPL crash: ~a" err-msg))
                         (send-event client-socket `(error ,err-msg)))))))

      (('env)
       (gaia-log "[SERVER] Client requested current environment variables.")
       (let ((bindings-promise (<- sandbox-actor 'definitions)))
         (on bindings-promise
             (lambda (bindings)
               (send-event client-socket `(env-list ,bindings))))))

      (('clear)
       (gaia-log (format #f "[SERVER] Clearing session ~a environment and history." session-id))
       (save-session session-id '())
       (let* ((event-sink (lambda (event) (send-event client-socket event)))
              (new-sb-actor (spawn ^repl-sandbox session-id event-sink permission-sink '()))
              (new-agent-actor (spawn ^agent-actor session-id new-sb-actor llm-client event-sink permission-sink)))
         (send-event client-socket '(final "Environment and history cleared."))
         (bcom (^session-orchestrator bcom session-id client-socket channel permission-sink new-sb-actor new-agent-actor llm-client '()) 'ok)))

      (('get-model)
       (send-event client-socket `(model-info ,(get-config 'model))))

      (('set-model new-model)
       (gaia-log (format #f "[SERVER] Hot-swapping model to: ~a" new-model))
       (set-config! 'model new-model)
       (send-event client-socket `(final ,(string-append "Model switched to: " new-model))))

      (('list-models)
       (let ((models '("gemma4:e2b" "gpt-4o" "claude-3.5-sonnet" "ollama/llama3" "local/ministral")))
         (send-event client-socket `(models-list ,models))))

      (('get-thinking)
       (let ((thinking (if (get-config 'thinking) "on" "off")))
         (send-event client-socket `(thinking-info ,thinking))))

      (('set-thinking state)
       (gaia-log (format #f "[SERVER] Set thinking mode to: ~a" state))
       (let* ((on? (or (eq? state #t) (string=? (format #f "~a" state) "on"))))
         (set-config! 'thinking on?)
         (send-event client-socket `(final ,(string-append "Thinking mode set to: " (if on? "on" "off"))))))

      (('ask query)
       (gaia-log (format #f "[SERVER] Received direct ASK request: ~a" query))
       (let* ((event-sink (lambda (event) (send-event client-socket event)))
              (chat-promise (<- llm-client 'chat session-id query (get-config 'model)
                                "You are a helpful Guile Scheme expert."
                                (get-config 'thinking) history event-sink)))
         (on chat-promise
             (lambda (response)
               (let* ((payload (assoc-ref response "payload"))
                      (content (if payload (assoc-ref payload "content") "Error: No payload")))
                 (send-event client-socket `(final ,content))
                 (let ((new-history (append history
                                            (list `(("role" . "user") ("content" . ,query))
                                                  `(("role" . "assistant") ("content" . ,content))))))
                   (save-session session-id new-history)
                   (<- self 'update-history new-history))))
             #:catch (lambda (err)
                       (send-event client-socket `(error ,(format #f "Ask Error: ~a" err)))))))

      (('session new-id)
       (if (string-null? new-id)
           (send-event client-socket `(final ,(string-append "Current session ID: " session-id)))
           (begin
             (gaia-log (format #f "[SERVER] Swapping session to: ~a" new-id))
             (let* ((new-history (load-session new-id))
                    (event-sink (lambda (event) (send-event client-socket event)))
                    (new-sb-actor (spawn ^repl-sandbox new-id event-sink permission-sink new-history))
                    (new-agent-actor (spawn ^agent-actor new-id new-sb-actor llm-client event-sink permission-sink)))
               (with-output-to-file ".last_session" (lambda () (display new-id)))
               (send-event client-socket `(final ,(string-append "Session switched to: " new-id)))
               (bcom (^session-orchestrator bcom new-id client-socket channel permission-sink new-sb-actor new-agent-actor llm-client new-history) 'ok)))))

      (('list-sessions)
       (let ((sessions (if (file-exists? "sessions")
                           (let ((files (scandir "sessions")))
                             (map (lambda (f) (substring f 0 (- (string-length f) 5)))
                                  (filter (lambda (f) (string-suffix? ".json" f))
                                          files)))
                           '())))
         (send-event client-socket `(session-list ,sessions))))

      (('get-history)
       (send-event client-socket `(history-list ,(clean-history history))))

      (('help)
       (let ((help-text "Available Commands:
  /help             - Show this help message
  /exit, /quit      - Exit the CLI
  /session [id]     - Show or switch current session
  /sessions         - List available sessions on server
  /history          - Show conversation history
  /clear            - Clear current session history and environment
  /env              - Show variables defined in REPL
  /eval <scheme>    - Execute Scheme code directly in REPL
  /ask <query>      - Ask a one-off question to AI (no recursion)
  /model [name]     - Show or change the active LLM model
  /models           - List available models
  /thinking [on|off]- Enable or disable reasoning mode"))
         (send-event client-socket `(final ,help-text))))

      (other
       (gaia-log (format #f "[SERVER] Unknown request command: ~s. Terminating socket." other))
       (close-port client-socket)))] ) )
