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
  #:use-module (gaia com)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia cognitive-state)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-memory)
  #:use-module (gaia workspace)
  #:use-module (gaia deliberative-processor)
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

(define (submit-cognitive-object! cognitive-session co priority origin)
  "Submit a CO to the session's GCAS workspace and require its admission."
  (session-submit! cognitive-session co #:priority priority #:origin origin)
  (let ((admitted (session-advance! cognitive-session)))
    (unless (and admitted (equal? (co-id admitted) (co-id co)))
      (error "Cognitive Object was not admitted by Control" (co-id co)))
    co))

(define (cognitive-event-summary cognitive-session)
  (map (lambda (event)
         `((id . ,(event-id event))
           (type . ,(event-type event))
           (origin . ,(event-origin event))))
       (state-events (session-state cognitive-session))))

(define (finish-cognitive-process! cognitive-session outcome)
  "End one cognitive process and release bounded working-state capacity.
The CO graph and durable memory remain available for audit and retrieval."
  (session-emit! cognitive-session 'ProcessTerminated outcome #:origin 'CONTROL)
  (session-clear-workspace! cognitive-session))

;; Session Orchestrator Actor
(define-actor (^session-orchestrator bcom session-id client-socket channel permission-sink sandbox-actor agent-actor llm-client history model thinking #:optional (workspace-dir #f) (cognitive-session (make-cognitive-session #:memory-path (string-append "sessions/" session-id ".gcas-memory.scm"))))
  #:self self
  (methods
   [(update-history new-history)
    (bcom (^session-orchestrator bcom session-id client-socket channel permission-sink sandbox-actor agent-actor llm-client new-history model thinking workspace-dir cognitive-session) 'ok)]

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

      (('eval task . retry-args)
       (let ((retries (if (null? retry-args) 0 (car retry-args)))
             (max-retries 3))
         (gaia-log (format #f "[SERVER] Received prompt: ~a (attempt ~a/~a)" task retries max-retries))
         (let* ((event-sink (lambda (event) (send-event client-socket event)))
                (chat-promise (<- llm-client 'chat session-id task model
                                  (get-system-prompt)
                                  thinking history event-sink)))
           (on chat-promise
               (lambda (response)
                 (let* ((payload (assoc-ref response "payload"))
                        (err (assoc-ref response "error"))
                        (response-text (if payload
                                           (assoc-ref payload "content")
                                           (string-append "Error from LLM API: " (if (string? err) err (format #f "~a" err))))))
                   (if (and err (string=? err "user-interrupt"))
                       (begin
                         (gaia-log "[SERVER] Chat interrupted by user.")
                         (send-event client-socket `(error "user-interrupt")))
                       (let ((action-code (extract-code response-text)))
                         (if action-code
                             ;; Default Mode: Interactive Notebook (single-step)
                             (begin
                               (gaia-log "[SERVER] LLM initiated code execution. Executing once (notebook style).")
                               (send-event client-socket `(code ,action-code))
                               (gaia-log (string-append C-BOLD C-CYAN "\n[GAIA] Executing Scheme Code:\n" C-RESET action-code "\n"))
                               (let ((eval-promise (<- sandbox-actor 'eval action-code)))
                                 (on eval-promise
                                     (lambda (eval-res)
                                       (match eval-res
                                         (('ok res)
                                          ;; Success: show result, save history, finalize this turn
                                          (send-event client-socket `(result ,res))
                                          (gaia-log (string-append C-GREEN "\n[REPL] Success:\n" C-RESET res "\n"))
                                          (let* ((updated-history (append history
                                                                          (list `(("role" . "user") ("content" . ,task))
                                                                                `(("role" . "assistant") ("content" . ,response-text))
                                                                                `(("role" . "user") ("content" . ,(string-append "[System REPL Output]:\n" res)))))))
                                            (gaia-log (format #f "[SERVER] Notebook step completed. Saving session ~a." session-id))
                                            (save-session session-id updated-history)
                                            (with-output-to-file ".last_session" (lambda () (display session-id)))
                                            ;; Send notebook-done: the client already displayed the code and result,
                                            ;; so we don't need a "Final Answer" heading.
                                            (send-event client-socket `(notebook-done ""))
                                            (<- self 'update-history updated-history)))
                                         (('error type msg)
                                          ;; Error: show the error in the client
                                          (let* ((err-msg (string-append "Runtime Error (" (symbol->string type) "): " msg)))
                                            (send-event client-socket `(repl-error ,err-msg))
                                            (gaia-log (string-append C-RED "\n[REPL] Runtime Error:\n" C-RESET err-msg "\n"))
                                            (let* ((updated-history (append history
                                                                            (list `(("role" . "user") ("content" . ,task))
                                                                                  `(("role" . "assistant") ("content" . ,response-text))
                                                                                  `(("role" . "user") ("content" . ,(string-append "[System REPL Error]:\n" err-msg "\nPlease fix the code and try again.")))))))
                                              (save-session session-id updated-history)
                                              (<- self 'update-history updated-history)
                                              (if (< retries max-retries)
                                                  ;; Re-invoke LLM with error context for self-correction
                                                  (let ((followup-prompt (string-append "The code you wrote produced an error:\n" err-msg "\nPlease fix the code.")))
                                                    (gaia-log (format #f "[SERVER] Code execution failed. Re-invoking LLM for self-correction (attempt ~a/~a)." (+ retries 1) max-retries))
                                                    (<- self 'handle-message `(eval ,followup-prompt ,(+ retries 1))))
                                                  ;; Max retries reached — give up and report the error
                                                  (begin
                                                    (gaia-log "[SERVER] Max self-correction retries reached. Sending error as final.")
                                                    (send-event client-socket `(final ,(string-append "Failed after " (number->string max-retries) " correction attempts. Last error:\n" err-msg))))))))))
                                     #:catch (lambda (err)
                                               (send-event client-socket `(error ,(format #f "Initial code execution crash: ~a" err)))))))
                             ;; Conversational reply
                             (let* ((prose (clean-assistant-content response-text))
                                    (updated-history (append history
                                                             (list `(("role" . "user") ("content" . ,task))
                                                                   `(("role" . "assistant") ("content" . ,response-text))))))
                               (gaia-log "[SERVER] LLM responded conversationally.")
                               (send-event client-socket `(final ,prose))
                               (save-session session-id updated-history)
                               (with-output-to-file ".last_session" (lambda () (display session-id)))
                               (<- self 'update-history updated-history)))))))
               #:catch (lambda (err)
                         (send-event client-socket `(error ,(format #f "LLM request failed: ~a" err))))))))

      (('solve task)
       (gaia-log (format #f "[SERVER] Received solve task: ~a" task))
       (let ((question-co (make-cognitive-object 'question task #:provenance 'USER))
             (goal-co (make-cognitive-object 'goal task #:provenance 'USER)))
         (submit-cognitive-object! cognitive-session question-co 10 'USER)
         (submit-cognitive-object! cognitive-session goal-co 100 'USER)
         (memory-store! (session-memory cognitive-session) question-co)
         (memory-store! (session-memory cognitive-session) goal-co)
         (let* ((selected-memory (memory-retrieve (session-memory cognitive-session) task))
                (context (reconstruct-context goal-co
                                              (workspace-active (session-workspace cognitive-session))
                                              selected-memory
                                              #:constraints '("Use an explicit Action before requesting execution."
                                                              "Do not present an execution result as a world fact without verification.")))
                (event-sink (lambda (event) (send-event client-socket event)))
                ;; History remains an episodic record.  It is not prompt memory.
                (chat-promise (<- llm-client 'chat session-id context model
                                  (get-solver-system-prompt) thinking '() event-sink)))
         (on chat-promise
             (lambda (response)
               (let* ((payload (assoc-ref response "payload"))
                      (err (assoc-ref response "error"))
                      (response-text (if payload (assoc-ref payload "content")
                                         (string-append "Error from LLM API: "
                                                        (if (string? err) err (format #f "~a" err))))))
                 (if (and err (string=? err "user-interrupt"))
                     (send-event client-socket `(error "user-interrupt"))
                     (let* ((hypothesis-co (make-cognitive-object 'hypothesis response-text #:provenance 'LLM))
                            (action-code (extract-code response-text))
                            (updated-history (append history
                                                     (list `(("role" . "user") ("content" . ,task))
                                                           `(("role" . "assistant") ("content" . ,response-text))))))
                       (submit-cognitive-object! cognitive-session hypothesis-co 70 'LLM)
                       (session-emit! cognitive-session 'HypothesisProposed hypothesis-co #:origin 'LLM)
                       (if (not action-code)
                           (begin
                             (save-session session-id updated-history)
                             (send-event client-socket
                                         `(final ,(string-append
                                                   "INSUFFICIENT_INFORMATION: the model produced an unverified hypothesis.\n"
                                                   (clean-assistant-content response-text))))
                             (<- self 'update-history updated-history)
                             (finish-cognitive-process! cognitive-session 'INSUFFICIENT_INFORMATION))
                           (let ((action-co (make-cognitive-object 'action action-code #:provenance 'LLM
                                                                    #:relations `((tests . ,(co-id hypothesis-co))))))
                             (submit-cognitive-object! cognitive-session action-co 85 'PLANNER)
                             (session-emit! cognitive-session 'ActionRequested action-co #:origin 'CONTROL)
                             (send-event client-socket `(code ,action-code))
                             (let ((eval-promise (<- sandbox-actor 'eval action-code)))
                               (on eval-promise
                                   (lambda (eval-res)
                                     (match eval-res
                                       (('ok res)
                                        (let ((result-co
                                               (make-cognitive-object 'result res #:provenance 'REPL
                                                                      #:relations `((produced-by . ,(co-id action-co))))))
                                          (session-record-result! cognitive-session (co-id action-co) result-co)
                                          (let ((observation-claim
                                                 (deliberate-execution!
                                                  cognitive-session action-co result-co
                                                  (lambda (approved-action observed-result)
                                                    ;; This verifies only the bounded observation:
                                                    ;; the approved Action produced this REPL Result.
                                                    (and (eq? (co-type approved-action) 'action)
                                                         (eq? (co-type observed-result) 'result)
                                                         (assoc-ref (co-relations observed-result) 'produced-by)))
                                                  #:claim-content
                                                  (string-append "The approved action produced the observed REPL output: " res))))
                                            (session-emit! cognitive-session 'ReflectionRaised observation-claim #:origin 'METACOGNITION)
                                            (save-session session-id updated-history)
                                            (send-event client-socket `(result ,res))
                                            (send-event client-socket
                                                        `(final ,(string-append
                                                                  "INCONCLUSIVE: verified execution observation recorded.\n"
                                                                  (co-content observation-claim)
                                                                  "\nThe original question is not accepted as true without independent evidence.")))
                                            (<- self 'update-history updated-history)
                                            (finish-cognitive-process! cognitive-session 'INCONCLUSIVE))))
                                       (('error type msg)
                                        (let ((err-msg (string-append "Runtime Error (" (symbol->string type) "): " msg)))
                                          (let ((failure-co
                                                 (make-cognitive-object 'result err-msg #:provenance 'REPL
                                                                        #:relations `((produced-by . ,(co-id action-co))))))
                                            (session-record-failure! cognitive-session (co-id action-co) failure-co)
                                          (send-event client-socket `(repl-error ,err-msg))
                                          (send-event client-socket `(final ,(string-append "GCAS action failed: " err-msg)))
                                            (session-emit! cognitive-session 'ReflectionRaised failure-co #:origin 'METACOGNITION)
                                            (finish-cognitive-process! cognitive-session 'FAILED)))))
                                   #:catch (lambda (err)
                                             (send-event client-socket `(error ,(format #f "GCAS action execution crash: ~a" err)))))))))))
             #:catch (lambda (err)
                       (send-event client-socket `(error ,(format #f "LLM request failed: ~a" err))))))))))

      ;; Explicit compatibility path for the legacy recursive LLM–REPL loop.
      ;; It is an investigation processor, not the default cognitive control loop.
      (('investigate task)
       (gaia-log (format #f "[SERVER] Received legacy investigation task: ~a" task))
       (let-values (((investigation-promise resolve-investigation) (new-promise-pair)))
         (<- agent-actor 'solve task 0 history resolve-investigation model thinking)
         (on investigation-promise
             (lambda (result-pair)
               (let ((answer (car result-pair))
                     (updated-history (cdr result-pair)))
                 (save-session session-id updated-history)
                 (send-event client-socket `(final ,answer))
                 (<- self 'update-history updated-history)))
             #:catch (lambda (err)
                       (send-event client-socket `(error ,(format #f "Legacy investigation failed: ~a" err)))))))

      (('repl code)
       (gaia-log (format #f "[SERVER] Received REPL code execution request."))
       (let* ((action-co (make-cognitive-object 'action code #:provenance 'USER))
              (_ (submit-cognitive-object! cognitive-session action-co 50 'USER))
              (before-promise (<- sandbox-actor 'definitions)))
         (on before-promise
             (lambda (before-defs)
               (let ((eval-promise (<- sandbox-actor 'eval code)))
                 (on eval-promise
                     (lambda (eval-res)
                       (match eval-res
                         (('ok val-str)
                          (session-record-result!
                           cognitive-session (co-id action-co)
                           (make-cognitive-object 'result val-str #:provenance 'REPL
                                                  #:relations `((produced-by . ,(co-id action-co)))))
                          (gaia-log (format #f "[SERVER] REPL success. Result: ~a" val-str))
                          (let ((after-promise (<- sandbox-actor 'definitions)))
                            (on after-promise
                                (lambda (after-defs)
                                  (if (not (equal? before-defs after-defs))
                                      ;; Mutated state! Send public result and save history.
                                      (let ((updated-history (append history
                                                                     (list `(("role" . "user-repl")
                                                                             ("content" . ,(string-append "```repl\n" code "\n```\nResult:\n" val-str)))))))
                                        (save-session session-id updated-history)
                                        (send-event client-socket `(repl-result ,val-str))
                                        (<- self 'update-history updated-history))
                                      ;; No state change! Send private result.
                                      (send-event client-socket `(repl-private-result ,val-str)))))))
                         (('error type msg)
                          (let ((err-msg (format #f "REPL Error (~a): ~a" type msg)))
                            (session-record-failure!
                             cognitive-session (co-id action-co)
                             (make-cognitive-object 'result err-msg #:provenance 'REPL
                                                    #:relations `((produced-by . ,(co-id action-co)))))
                            (gaia-log (format #f "[SERVER] REPL error: ~a" err-msg))
                            (send-event client-socket `(repl-private-result-error ,err-msg))))))
                     #:catch (lambda (err)
                               (let ((err-msg (format #f "REPL Crash: ~a" err)))
                                 (gaia-log (format #f "[SERVER] REPL crash: ~a" err-msg))
                                 (send-event client-socket `(repl-private-result-error ,err-msg))))))))))

      (('env)
       (gaia-log "[SERVER] Client requested current environment variables.")
       (let ((bindings-promise (<- sandbox-actor 'definitions)))
         (on bindings-promise
             (lambda (bindings)
               (send-event client-socket `(env-list ,bindings))))))

      ;; Internal protocol endpoint for observability and integration tests.
      ;; The interactive client does not expose this until it can render CO graphs.
      (('get-cognitive-events)
       (send-event client-socket
                   `(cognitive-events ,(cognitive-event-summary cognitive-session))))

      (('clear)
       (gaia-log (format #f "[SERVER] Clearing session ~a environment and history." session-id))
       (save-session session-id '())
       (let* ((event-sink (lambda (event) (send-event client-socket event)))
              (new-sb-actor (spawn ^repl-sandbox session-id event-sink permission-sink '() workspace-dir))
              (new-agent-actor (spawn ^agent-actor session-id new-sb-actor llm-client event-sink permission-sink)))
         (send-event client-socket '(final "Environment and history cleared."))
         (bcom (^session-orchestrator bcom session-id client-socket channel permission-sink new-sb-actor new-agent-actor llm-client '() model thinking workspace-dir (make-cognitive-session #:memory-path (string-append "sessions/" session-id ".gcas-memory.scm"))) 'ok)))

      (('get-model)
       (send-event client-socket `(model-info ,model)))

      (('set-model new-model)
       (let ((new-model-str (format #f "~a" new-model)))
         (gaia-log (format #f "[SERVER] Hot-swapping model to: ~a" new-model-str))
         (send-event client-socket `(final ,(string-append "Model switched to: " new-model-str)))
         (bcom (^session-orchestrator bcom session-id client-socket channel permission-sink sandbox-actor agent-actor llm-client history new-model-str thinking workspace-dir cognitive-session) 'ok)))

      (('list-models)
       (let ((models-promise (<- llm-client 'get-models)))
         (on models-promise
             (lambda (models)
               (if (and (list? models) (not (null? models)) (string? (car models)))
                   (send-event client-socket `(models-list ,models))
                   (send-event client-socket `(models-list '("gemma4:e2b" "gemma4:e4b" "gemini-2.0-flash" "gpt-4o" "claude-3.5-sonnet")))))
             #:catch (lambda (err)
                       (send-event client-socket `(models-list '("gemma4:e2b" "gemma4:e4b" "gemini-2.0-flash" "gpt-4o" "claude-3.5-sonnet")))))))

      (('get-thinking)
       (let ((thinking-str (if thinking "on" "off")))
         (send-event client-socket `(thinking-info ,thinking-str))))

      (('set-thinking state)
       (gaia-log (format #f "[SERVER] Set thinking mode to: ~a" state))
       (let* ((on? (or (eq? state #t) (string=? (format #f "~a" state) "on"))))
         (send-event client-socket `(final ,(string-append "Thinking mode set to: " (if on? "on" "off"))))
         (bcom (^session-orchestrator bcom session-id client-socket channel permission-sink sandbox-actor agent-actor llm-client history model on? workspace-dir cognitive-session) 'ok)))

      (('get-state-injection)
       (let ((state-str (if (get-config 'state-injection) "on" "off")))
         (send-event client-socket `(state-injection-info ,state-str))
         (send-event client-socket `(final ,(string-append "State injection is currently: " state-str)))))

      (('set-state-injection state)
       (gaia-log (format #f "[SERVER] Set state-injection to: ~a" state))
       (let* ((on? (or (eq? state #t) (string=? (format #f "~a" state) "on"))))
         (set-config! 'state-injection on?)
         (send-event client-socket `(final ,(string-append "State injection set to: " (if on? "on" "off"))))
         'ok))

      (('get-wisp-mode)
       (let ((wisp-str (if (get-config 'wisp-mode) "on" "off")))
         (send-event client-socket `(wisp-mode-info ,wisp-str))
         (send-event client-socket `(final ,(string-append "Wisp mode is currently: " wisp-str)))))

      (('set-wisp-mode state)
       (gaia-log (format #f "[SERVER] Set wisp-mode to: ~a" state))
       (let* ((on? (or (eq? state #t) (string=? (format #f "~a" state) "on"))))
         (set-config! 'wisp-mode on?)
         (send-event client-socket `(final ,(string-append "Wisp mode set to: " (if on? "on" "off"))))
         'ok))

      (('ask query)
       (gaia-log (format #f "[SERVER] Received direct ASK request: ~a" query))
       (let* ((event-sink (lambda (event) (send-event client-socket event)))
              (chat-promise (<- llm-client 'chat session-id query model
                                "You are a helpful Guile Scheme expert."
                                thinking history event-sink)))
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

      (('session . args)
       (let* ((new-id (if (null? args) "" (car args)))
              (new-ws (if (and (not (null? args)) (not (null? (cdr args)))) (cadr args) workspace-dir)))
         (if (string-null? new-id)
             (send-event client-socket `(final ,(string-append "Current session ID: " session-id)))
             (begin
               (gaia-log (format #f "[SERVER] Swapping session to: ~a" new-id))
               (let* ((new-history (load-session new-id))
                      (event-sink (lambda (event) (send-event client-socket event)))
                      (new-sb-actor (spawn ^repl-sandbox new-id event-sink permission-sink new-history new-ws))
                      (new-agent-actor (spawn ^agent-actor new-id new-sb-actor llm-client event-sink permission-sink)))
                 (with-output-to-file ".last_session" (lambda () (display new-id)))
                 (send-event client-socket `(final ,(string-append "Session switched to: " new-id)))
                 (bcom (^session-orchestrator bcom new-id client-socket channel permission-sink new-sb-actor new-agent-actor llm-client new-history model thinking new-ws (make-cognitive-session #:memory-path (string-append "sessions/" new-id ".gcas-memory.scm"))) 'ok))))))

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
  /solve <query>    - Run the GCAS cognitive process (default for normal input)
  /investigate <q>  - Use the legacy recursive LLM–REPL investigation processor
  /ask <query>      - Ask the LLM without initiating a GCAS process
  /cognitive-events - Show the current session's GCAS event trace
  /ask <query>      - Ask a one-off question to AI (no recursion)
  /model [name]     - Show or change the active LLM model
  /models           - List available models
  /thinking [on|off]- Enable or disable reasoning mode
  /state [on|off]   - Enable or disable REPL state injection header
  /wisp [on|off]    - Enable or disable Wisp-mode instructions"))
          (send-event client-socket `(final ,help-text))))

      (other
       (gaia-log (format #f "[SERVER] Unknown request command: ~s. Terminating socket." other))
       (close-port client-socket)))] ) )
