(define-module (gaia actors)
  #:use-module (ice-9 match)
  #:use-module (ice-9 ftw)
  #:use-module (fibers)
  #:use-module (fibers channels)
  #:use-module (goblins)
  #:use-module (goblins actor-lib methods)
  #:use-module (goblins actor-lib joiners)
  #:use-module (srfi srfi-11)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 suspendable-ports)
  #:use-module (ice-9 threads)
  #:use-module (gaia sandbox)
  #:use-module (gaia executor)
  #:use-module (gaia rlm-env)
  #:use-module (gaia llm-client)
  #:use-module (gaia config)
  #:use-module (gaia utils)
  #:use-module (gaia core)
  #:export (^repl-sandbox
            ^llm-client
            ^agent-actor
            ^session-orchestrator
            current-<-np-extern))

(define current-<-np-extern (make-parameter <-np-extern))

;; Helpers
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

(define (replay-history env history)
  (for-each (lambda (turn)
              (let ((role (or (assoc-ref turn 'role) (assoc-ref turn "role")))
                    (trajectory (or (assoc-ref turn 'trajectory) (assoc-ref turn "trajectory"))))
                (if trajectory
                    (for-each (lambda (step)
                                (let ((step-role (or (assoc-ref step 'role) (assoc-ref step "role")))
                                      (step-content (or (assoc-ref step 'content) (assoc-ref step "content"))))
                                  (when (and step-role (string=? (format #f "~a" step-role) "assistant") step-content)
                                    (let ((code (extract-code step-content)))
                                      (when code
                                        (rlm-eval! env code #:permission-handler (lambda (_) #t)))))))
                              (if (vector? trajectory) (vector->list trajectory) trajectory))
                    (let ((content (or (assoc-ref turn 'content) (assoc-ref turn "content"))))
                      (when (and role (string=? (format #f "~a" role) "assistant") content)
                        (let ((code (extract-code content)))
                          (when code
                            (rlm-eval! env code #:permission-handler (lambda (_) #t)))))))))
            history))

(define (new-promise-pair)
  (spawn-promise-and-resolver))

;; 1. Sandbox Actor
(define-actor (^repl-sandbox bcom session-id event-handler permission-handler history)
  (let ((env (make-rlm-env session-id event-handler permission-handler)))
    (rlm-inject! env 'llm-query
      (lambda (prompt)
        (let* ((sub-session (string-append session-id "-sub-" (number->string (random 1000000000))))
               (response (chat-with-llm sub-session prompt (get-config 'model) (or (get-config 'system-prompt) SYSTEM_PROMPT) #:history '()))
               (payload (assoc-ref response "payload")))
          (if payload
              (assoc-ref payload "content")
              "Error: No response from sub-LLM"))))
    (when (and history (not (null? history)))
      (replay-history env history))
    (methods
     [(eval code)
      (rlm-execute env code)]
     [(definitions)
      (rlm-env-user-bindings env)]
     [(save-checkpoint)
      (let ((sb (rlm-env-sandbox env)))
        (backup-module (sandbox-module sb) (sandbox-initial-symbols sb)))]
     [(restore-checkpoint backup)
      (let ((sb (rlm-env-sandbox env)))
        (restore-module! (sandbox-module sb) (sandbox-initial-symbols sb) backup)
        'ok)]
     [(fork)
      (let* ((sb (rlm-env-sandbox env))
             (cloned-sb (fork-sandbox sb))
             (cloned-env (%make-rlm-env cloned-sb (rlm-env-history env) (rlm-env-injected-bindings env))))
        (spawn ^repl-sandbox-from-env cloned-env) ) ] ) ) )

(define-actor (^repl-sandbox-from-env bcom env)
  (methods
   [(eval code)
    (rlm-execute env code)]
   [(definitions)
    (rlm-env-user-bindings env)]
   [(save-checkpoint)
    (let ((sb (rlm-env-sandbox env)))
      (backup-module (sandbox-module sb) (sandbox-initial-symbols sb)))]
   [(restore-checkpoint backup)
    (let ((sb (rlm-env-sandbox env)))
      (restore-module! (sandbox-module sb) (sandbox-initial-symbols sb) backup)
      'ok)]
   [(fork)
    (let* ((sb (rlm-env-sandbox env))
           (cloned-sb (fork-sandbox sb))
           (cloned-env (%make-rlm-env cloned-sb (rlm-env-history env) (rlm-env-injected-bindings env))))
      (spawn ^repl-sandbox-from-env cloned-env) ) ] ) )

(define (clear-goblins-context!)
  "Reset Goblins parameters in the current fiber's dynamic environment."
  (let ((current-syscaller (false-if-exception (@@ (goblins core) current-syscaller)))
        (current-sleep-profile (false-if-exception (@@ (goblins core) current-sleep-profile)))
        (current-vat (false-if-exception (@@ (goblins repl) current-vat)))
        (current-repl-vat (false-if-exception (@@ (goblins vrun) current-repl-vat))))
    (when current-syscaller (current-syscaller #f))
    (when current-sleep-profile (current-sleep-profile #f))
    (when current-vat (current-vat #f))
    (when current-repl-vat (current-repl-vat #f))))

;; 2. LLM Client Actor
(define-actor (^llm-client bcom session-vat)
  #:self self
  (methods
   [(chat session-id prompt model system-prompt think history stream-callback #:optional (role "user"))
    (let-values (((promo resolver) (spawn-promise-and-resolver)))
      (let ((channel (make-channel)))
        ;; Spawn a POSIX thread to handle the synchronous HTTP request
        (call-with-new-thread
         (lambda ()
           (parameterize ((current-read-waiter (@@ (ice-9 suspendable-ports) default-read-waiter))
                          (current-write-waiter (@@ (ice-9 suspendable-ports) default-write-waiter)))
             (catch #t
               (lambda ()
                 (let ((res (chat-with-llm session-id prompt model system-prompt
                                           #:think think
                                           #:history history
                                           #:role role
                                           #:stream-callback (lambda (evt)
                                                               (put-message channel `(stream ,evt))))))
                   (put-message channel `(done ,res))))
               (lambda (key . args)
                 (put-message channel `(error ,(format #f "~s ~s" key args))))))))

        ;; Spawn a fiber to read from the channel and fulfill the resolver
        (spawn-fiber
         (lambda ()
           (clear-goblins-context!)
           (let loop ()
             (let ((msg (get-message channel)))
               (match msg
                 (('stream evt)
                  (when stream-callback
                    (stream-callback evt))
                  (loop))
                 (('done res)
                  ((current-<-np-extern) resolver 'fulfill res))
                 (('error err)
                  ((current-<-np-extern) resolver 'fulfill `(("error" . ,err))))))))))
      promo)]))


;; 3. Agent Actor (Recursive Language Model Loop)
(define-actor (^agent-actor bcom session-id sandbox llm-client event-handler permission-handler)
  #:self self
  (methods
   [(solve task depth current-history resolve-promise)
    (<- self 'solve-step task depth current-history current-history 1 '() task resolve-promise)
    'ok]

   [(solve-step task depth outer-history history step transcript last-output resolve-promise)
    (check-interrupt!)
    (if (> depth MAX-RECURSION-DEPTH)
        (begin
          (gaia-log "\n[GAIA] Max recursion depth reached. Returning current state.\n")
          (let* ((loop-steps (drop history (length outer-history)))
                 (clean-history (append outer-history
                                        (list `(("role" . "user") ("content" . ,task))
                                              `(("role" . "assistant") ("content" . ,last-output) ("trajectory" . ,(list->vector loop-steps)))))))
            (<- resolve-promise 'fulfill (cons last-output clean-history))))
        (begin
          (when event-handler (event-handler `(status ,(format #f "Agent Depth ~a (Step ~a)..." depth step))))
          (let* ((prompt last-output)
                 (stream-callback (lambda (evt)
                                    (when event-handler
                                      (event-handler evt)))))
            (let ((chat-promise (<- llm-client 'chat session-id prompt (get-config 'model)
                                    (or (get-config 'system-prompt) SYSTEM_PROMPT)
                                    (get-config 'thinking) history stream-callback
                                    (if (null? transcript) "user" "system"))))
              (on chat-promise
                  (lambda (response)
                    (let* ((payload (assoc-ref response "payload"))
                           (response-text (if payload
                                              (assoc-ref payload "content")
                                              (let ((err (assoc-ref response "error")))
                                                (if err
                                                    (string-append "Error from LLM API: " (if (string? err) err (format #f "~a" err)))
                                                    "Error: No payload in response"))))
                           (reasoning-text (if payload (assoc-ref payload "reasoning") ""))
                           (prose (clean-assistant-content response-text))
                           (conf-val (extract-confidence response-text)))

                      (when (and reasoning-text (> (string-length reasoning-text) 0))
                        (when event-handler (event-handler `(thought-full ,reasoning-text)))
                        (gaia-log (string-append C-GREY "[GAIA] Thinking Complete." C-RESET "\n")))

                      (when (> (string-length prose) 0)
                        (when event-handler (event-handler `(analysis ,prose)))
                        (gaia-log (string-append C-BLUE "\n[GAIA] Analysis: " C-RESET (markdown->ansi prose) "\n")))

                      (let* ((updated-transcript
                              (append transcript
                                      (if (= step 1)
                                          (list (cons "original-task" last-output)
                                                (cons "assistant" (truncate-for-transcript response-text))
                                                (cons "user" last-output))
                                          (list (cons "user" last-output)
                                                (cons "assistant" (truncate-for-transcript response-text)))))))

                        (let ((action-code (extract-code response-text))
                              (action-delegate (extract-delegation response-text))
                              (final-sig (extract-final-signal response-text)))
                          (cond
                           ;; Case A: Delegation
                           (action-delegate
                            (match action-delegate
                              (('delegate goal context-str)
                               (gaia-log (string-append C-BOLD C-YELLOW "\n[GAIA] Spawning Sub-Agent (Delegation):\n" C-RESET "Goal: " goal "\nContext: " context-str "\n"))
                               (let* ((sub-vat (spawn-vat))
                                      (sub-session-id (string-append session-id "-sub-" (number->string (random 1000000000))))
                                      (sub-agent
                                       (with-vat sub-vat
                                         (spawn ^agent-actor sub-session-id
                                                (spawn ^repl-sandbox sub-session-id event-handler permission-handler '())
                                                llm-client event-handler permission-handler))))
                                 (let-values (((sub-promise resolve-sub) (new-promise-pair)))
                                   (<- sub-agent 'solve goal (+ depth 1) '() resolve-sub)
                                   (on sub-promise
                                       (lambda (sub-res-pair)
                                         (let* ((sub-ans (car sub-res-pair))
                                                (formatted-sub-output (string-append "Sub-agent execution finished. Result: " sub-ans)))
                                           (gaia-log (string-append C-BOLD C-GREEN "\n[GAIA] Sub-Agent completed.\n" C-RESET "Result length: "
                                                                   (number->string (string-length sub-ans)) " chars\n"))
                                           (if final-sig
                                               (let* ((loop-steps (drop history (length outer-history)))
                                                      (clean-history (append outer-history
                                                                             (list `(("role" . "user") ("content" . ,task))
                                                                                   `(("role" . "assistant") ("content" . ,(match final-sig (('final ans) ans) (('final-var var) var) (_ "Sub-agent executed successfully")))
                                                                                         ("trajectory" . ,(list->vector loop-steps)))))))
                                                 (<- resolve-promise 'fulfill (cons (match final-sig (('final ans) ans) (('final-var var) var) (_ "Sub-agent executed successfully"))
                                                                                    clean-history)))
                                               (<- self 'solve-step task depth outer-history
                                                   (append history (list `(("role" . "system") ("content" . ,last-output))
                                                                         `(("role" . "assistant") ("content" . ,response-text))))
                                                   (+ step 1) updated-transcript formatted-sub-output resolve-promise))))
                                       #:catch (lambda (err)
                                                 (let ((err-str (format #f "Sub-agent failed: ~a" err)))
                                                   (<- self 'solve-step task depth outer-history
                                                       (append history (list `(("role" . "system") ("content" . ,last-output))
                                                                             `(("role" . "assistant") ("content" . ,response-text))))
                                                       (+ step 1) updated-transcript err-str resolve-promise)))))))
                              (_
                               (<- self 'solve-step task depth outer-history
                                   (append history (list `(("role" . "system") ("content" . ,last-output))
                                                         `(("role" . "assistant") ("content" . ,response-text))))
                                   (+ step 1) updated-transcript "Error: Invalid delegation format. Use (delegate \"Goal\" \"Context\")" resolve-promise))))

                           ;; Case B: Code execution
                           (action-code
                            (if (and action-code (> (string-length action-code) 0) (not (string=? action-code response-text)))
                                (begin
                                  (when event-handler (event-handler `(code ,action-code)))
                                  (gaia-log (string-append C-BOLD C-CYAN "\n[GAIA] Executing Scheme Code:\n" C-RESET action-code "\n"))
                                  (let ((eval-promise (<- sandbox 'eval action-code)))
                                    (on eval-promise
                                        (lambda (eval-res)
                                          (match eval-res
                                            (('ok result)
                                             (when event-handler (event-handler `(result ,result)))
                                             (gaia-log (string-append C-GREEN "\n[REPL] Success:\n" C-RESET result "\n"))
                                             (<- self 'solve-step task depth outer-history
                                                 (append history (list `(("role" . "system") ("content" . ,last-output))
                                                                       `(("role" . "assistant") ("content" . ,response-text))))
                                                 (+ step 1) updated-transcript (string-append "Code executed successfully. Result:\n" result) resolve-promise))
                                            (('error type msg)
                                             (let ((feedback (string-append "Runtime Error (" (symbol->string type) "): " msg)))
                                               (when event-handler (event-handler `(repl-error feedback)))
                                               (gaia-log (string-append C-RED "\n[REPL] Runtime Error:\n" C-RESET feedback "\n"))
                                               (<- self 'solve-step task depth outer-history
                                                   (append history (list `(("role" . "system") ("content" . ,last-output))
                                                                         `(("role" . "assistant") ("content" . ,response-text))))
                                                   (+ step 1) updated-transcript feedback resolve-promise)))))
                                        #:catch (lambda (err)
                                                  (let ((err-str (format #f "Sandbox evaluation crash: ~a" err)))
                                                    (<- self 'solve-step task depth outer-history
                                                        (append history (list `(("role" . "system") ("content" . ,last-output))
                                                                              `(("role" . "assistant") ("content" . ,response-text))))
                                                        (+ step 1) updated-transcript err-str resolve-promise))))))
                                (let* ((loop-steps (drop history (length outer-history)))
                                       (clean-history (append outer-history
                                                              (list `(("role" . "user") ("content" . ,task))
                                                                    `(("role" . "assistant") ("content" . ,response-text) ("trajectory" . ,(list->vector loop-steps)))))))
                                  (<- resolve-promise 'fulfill (cons response-text clean-history)))))

                           ;; Case C: Final Signal
                           ((and final-sig (match final-sig (('final ans) ans) (('final-var var) var) (_ #f))) =>
                            (lambda (answer)
                              (when event-handler (event-handler `(final ,answer)))
                              (if (equal? (car final-sig) 'final)
                                  (gaia-log (string-append C-BOLD "[GAIA] Final Answer: " C-RESET (markdown->ansi answer) "\n"))
                                  (gaia-log (string-append C-BOLD "[GAIA] Answer stored in: " C-RESET answer "\n")))
                              (let* ((loop-steps (drop history (length outer-history)))
                                     (clean-history (append outer-history
                                                            (list `(("role" . "user") ("content" . ,task))
                                                                  `(("role" . "assistant") ("content" . ,answer) ("trajectory" . ,(list->vector loop-steps)))))))
                                (<- resolve-promise 'fulfill (cons answer clean-history)))))

                           ;; Case D: High confidence
                           ((and conf-val (>= conf-val CONFIDENCE-THRESHOLD))
                            (when event-handler (event-handler `(final ,response-text)))
                            (gaia-log (string-append C-GREEN "\n[GAIA] ✓ High confidence (" (number->string conf-val) "%) - stopping." C-RESET "\n"))
                            (let* ((loop-steps (drop history (length outer-history)))
                                   (clean-history (append outer-history
                                                          (list `(("role" . "user") ("content" . ,task))
                                                                `(("role" . "assistant") ("content" . ,response-text) ("trajectory" . ,(list->vector loop-steps)))))))
                              (<- resolve-promise 'fulfill (cons response-text clean-history))))

                           ;; Case E: Fallback
                           (else
                            (when event-handler (event-handler `(final ,response-text)))
                            (let* ((loop-steps (drop history (length outer-history)))
                                   (clean-history (append outer-history
                                                          (list `(("role" . "user") ("content" . ,task))
                                                                `(("role" . "assistant") ("content" . ,response-text) ("trajectory" . ,(list->vector loop-steps)))))))
                              (<- resolve-promise 'fulfill (cons response-text clean-history)))))))))
                  #:catch (lambda (err)
                            (let ((err-msg (format #f "LLM Call Error: ~a" err)))
                              (gaia-log (string-append C-RED err-msg C-RESET "\n"))
                              (<- resolve-promise 'fulfill (cons err-msg history) ) ) ) ) ) ) ) ) ] ) )


;; 4. Session Orchestrator Actor
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

      (other
       (gaia-log (format #f "[SERVER] Unknown request command: ~s. Terminating socket." other))
       (close-port client-socket)))] ) )
