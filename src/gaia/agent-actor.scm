(define-module (gaia agent-actor)
  #:use-module (ice-9 match)
  #:use-module (goblins)
  #:use-module (goblins actor-lib methods)
  #:use-module (fibers)
  #:use-module (fibers channels)
  #:use-module (ice-9 threads)
  #:use-module (ice-9 suspendable-ports)
  #:use-module (gaia sandbox-actor)
  #:use-module (gaia config)
  #:use-module (gaia core)
  #:use-module (gaia executor)
  #:use-module (gaia llm-client)
  #:use-module (gaia utils)
  #:export (^llm-client
            ^agent-actor
            current-<-np-extern))

(define current-<-np-extern (make-parameter <-np-extern))

(define (new-promise-pair)
  (spawn-promise-and-resolver))

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

(define (consecutive-errors history)
  (let loop ((h (reverse history)) (count 0))
    (if (null? h)
        count
        (let* ((turn (car h))
               (role (or (assoc-ref turn 'role) (assoc-ref turn "role")))
               (content (or (assoc-ref turn 'content) (assoc-ref turn "content"))))
          (if (and role (or (string=? (format #f "~a" role) "user") (string=? (format #f "~a" role) "system")))
              (if (and content
                       (or (string-prefix? "Runtime Error" content)
                           (string-prefix? "REPL Error" content)
                           (string-prefix? "Error:" content)
                           (string-prefix? "Sub-agent failed" content)))
                  (loop (cdr h) (+ count 1))
                  (if (and role (string=? (format #f "~a" role) "system"))
                      (loop (cdr h) count)
                      count))
              (loop (cdr h) count))))))

;; LLM Client Actor
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

;; Agent Actor (Recursive Language Model Loop)
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
          (let ((err-count (consecutive-errors history)))
            (if (>= err-count 3)
                (begin
                  (gaia-log (string-append C-BOLD C-RED "\n[GAIA] Diagnostic Bailout: Consecutive errors detected. Spawning diagnostic sub-agent...\n" C-RESET))
                  (let* ((sub-vat (spawn-vat))
                         (sub-session-id (string-append session-id "-diag-" (number->string (random 1000000000))))
                         (sub-agent
                          (with-vat sub-vat
                            (spawn ^agent-actor sub-session-id
                                   (spawn ^repl-sandbox sub-session-id event-handler permission-handler '())
                                   llm-client event-handler permission-handler))))
                    (let-values (((sub-promise resolve-sub) (new-promise-pair)))
                      (<- sub-agent 'solve
                          (format #f "The main agent has encountered ~a consecutive errors. Last output: ~a. Diagnose the issue and write Scheme code to fix it." err-count last-output)
                          (+ depth 1) '() resolve-sub)
                      (on sub-promise
                          (lambda (sub-res-pair)
                            (let* ((sub-ans (car sub-res-pair))
                                   (formatted-sub-output (string-append "Diagnostic sub-agent completed. Suggestion/Fix:\n" sub-ans)))
                              (gaia-log (string-append C-BOLD C-GREEN "\n[GAIA] Diagnostic sub-agent completed.\n" C-RESET))
                              (<- self 'solve-step task depth outer-history
                                  (append history (list `(("role" . "system") ("content" . "Diagnostic sub-agent ran to debug consecutive errors."))
                                                        `(("role" . "assistant") ("content" . ,sub-ans))))
                                  (+ step 1) transcript formatted-sub-output resolve-promise)))
                          #:catch (lambda (err)
                                    (<- resolve-promise 'fulfill (cons (string-append "Failed with consecutive errors, diagnostic sub-agent also failed: " (format #f "~a" err)) history)))))))
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
                                    (<- resolve-promise 'fulfill (cons err-msg history)))))))))))] ) )
