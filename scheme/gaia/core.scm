(define-module (gaia core)
  #:use-module (gaia rai-client)
  #:use-module (gaia executor)
  #:use-module (gaia utils)
  #:use-module (ice-9 match)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 readline)
  #:use-module (ice-9 rdelim)
  #:use-module (srfi srfi-43)
  #:use-module (gaia config)
  #:export (start-gaia SYSTEM_PROMPT extract-code extract-final-signal extract-confidence rlm-loop))




(define C-RESET "\x1b[0m")
(define C-BOLD "\x1b[1m")
(define C-RED "\x1b[31m")
(define C-GREEN "\x1b[32m")
(define C-YELLOW "\x1b[33m")
(define C-BLUE "\x1b[34m")
(define C-CYAN "\x1b[36m")
(define C-GREY "\x1b[90m")

(define SYSTEM_PROMPT
  "# ROLE
You are GAIA (GNU AI Assistant), an advanced system operator.
Your primary goal is to solve technical tasks within a GNU Guix environment using GNU Guile/Scheme language (i.e. s-experssions or g-expressions).

# ENVIRONMENT & TOOLS
- Operating System: GNU Guix.
- Primary Language: Guile Scheme (S-expressions).
- Execution Method: You do not read large files directly. Instead, you generate Guile Scheme code that runs inside isolated 'guix shell --container' environments to investigate the system.

# RLM OPERATIONAL RULES
1. INVESTIGATE, DON'T READ: If a task involves large files (logs, source code, system state), do NOT ask the user to provide the text. Write a Guile script to explore the file.
2. RECURSIVE DELEGATION: If a task is complex or requires analyzing a specific component in isolation, DELEGATE it to a sub-agent.
   - To delegate, use a code block with language 'delegate' containing an S-expression: `(delegate \"Goal\" \"Context\")`.
   - The system will spawn a FRESH agent with only that goal and context.
   - The result will be returned to you.
3. DIRECT EXECUTION: If a task is simple, write a Guile Scheme script to execute it using `(system*)` or other Guile primitives.
   - Wrap Scheme code in triple backticks: ```scheme ... ```.

# COMPLETION SIGNALS
When you have solved the task completely, you MUST use one of these signals:
- FINAL(answer) - for direct text answers. Example: FINAL(The file contains 42 errors)
- FINAL_VAR(variable_name) - for answers stored in a variable from code execution.

After each step, rate your confidence that the task is fully complete on a scale of 0-100%:
- CONFIDENCE(score) - Example: CONFIDENCE(95) if you're very confident the task is done
- If CONFIDENCE >= 95%, the system will stop automatically
- If CONFIDENCE < 95%, continue investigating

CRITICAL RULE: NEVER mix tool execution (```scheme or ```delegate) and FINAL()/FINAL_VAR() in the exact same response!
You must output ONLY the code block, WAIT for the system to execute it, and then in the NEXT turn provide FINAL() based on the result.

# AVAILABLE TOOLS (Safe Standard Library)
The following functions are available in your environment from `(gaia tools)`. USE THEM instead of `system`.
- `(list-files path)`: Returns list of files in directory.
- `(read-file path)`: Returns content of file as string.
- `(write-file path content)`: Writes string to file.
- `(file-info path)`: Returns file metadata (size, type).
- `(search-file pattern path)`: Grep equivalent.
- `(run-sed expression path)`: Sed equivalent.
- `(run-awk program path)`: Awk equivalent.
- `(guile-syntax-check code-string)`: Validates Guile Scheme code syntax without evaluating.
- `(git-status)`: Returns a concise git status of the workspace (-s -b).
- `(git-diff [path])`: Returns git diff (optional filter by path).
- `(git-log [n])`: Returns recent git history (oneline format, n commits).
- `(guix-search query)`: Searches Guix packages.
- `(guix-package-info pkg)`: Shows Guix package details.

# GUILE SCHEME GUIDELINES
- Use functional programming patterns.
- Always include necessary modules.
- Focus on safety and precision.

# EXAMPLE TASK FLOW
User: \"Find errors in /var/log/syslog\"
GAIA Thinking:
1. File is large. I should delegate the analysis.
GAIA Output:
```delegate
(delegate \"Find all 'Permission Denied' errors\" \"File: /var/log/syslog\")
```
CONFIDENCE(30)

GAIA (System): Returns \"Result: Found 5 errors...\"
GAIA: \"The sub-agent found 5 errors. Summary: [details]. FINAL(Found 5 'Permission Denied' errors in /var/log/syslog) CONFIDENCE(100)\"
")

(define (extract-code response)
  "Extracts Scheme code from the LLM response (markdown code block)."
  (let ((str (if (string? response) response (scm->json response))))
    (if (string-contains str "```scheme")
        (let* ((start (+ (string-contains str "```scheme") 9))
               (end (string-contains str "```" start)))
          (substring str start end))
        #f)))

(define (extract-delegation response)
  "Extracts delegation S-expression from the LLM response."
  (let ((str (if (string? response) response (scm->json response))))
    (if (string-contains str "```delegate")
        (let* ((start (+ (string-contains str "```delegate") 11))
               (end (string-contains str "```" start))
               (sexp-str (substring str start end)))
          (catch #t
            (lambda () (with-input-from-string sexp-str read))
            (lambda _ #f)))
        #f)))

(define (extract-final-signal response)
  "Extracts FINAL() or FINAL_VAR() signal from LLM response."
  (let ((str (if (string? response) response (scm->json response))))
    (cond
     ((string-match "FINAL\\(([^)]+)\\)" str) =>
      (lambda (m) (list 'final (match:substring m 1))))
     ((string-match "FINAL_VAR\\(([^)]+)\\)" str) =>
      (lambda (m) (list 'final-var (match:substring m 1))))
     (else #f))))

(define (extract-confidence response)
  "Extracts CONFIDENCE(score) from LLM response. Returns number 0-100 or #f."
  (let ((str (if (string? response) response (scm->json response))))
    (cond
     ((string-match "CONFIDENCE\\(([0-9]+)\\)" str) =>
      (lambda (m)
        (let ((score (string->number (match:substring m 1))))
          (if (and score (>= score 0) (<= score 100))
              score
              #f))))
     (else #f))))

(define (handle-error error-type message depth)
  "Generates contextual feedback for errors."
  (case error-type
    ((syntax)
     (string-append "Syntax Error in your Scheme code: " message "\nPlease check parentheses and syntax."))
    ((permission)
     (string-append "Security Violation: " message "\nYou must use only allowed primitives. Do not use 'system' or file modification commands."))
    ((runtime)
     (string-append "Runtime Error: " message "\nReview the logic and try debugging with display statements."))
    (else
     (string-append "Unknown Error: " message))))

(define MAX-RECURSION-DEPTH 15)
(define CONFIDENCE-THRESHOLD 95)

(define (rlm-loop session-id last-output depth)
  (if (> depth MAX-RECURSION-DEPTH)
      (begin
        (display "\n[GAIA] Max recursion depth reached. Returning current state.\n")
        last-output)
      (begin
        (display (string-append C-GREY "\n[GAIA] Thinking (Depth " (number->string depth) ")..." C-RESET "\n"))
        (let* ((response (chat-with-rai session-id last-output (get-config 'model) SYSTEM_PROMPT))
               (payload (assoc-ref response "payload"))
               (response-text (if payload (assoc-ref payload "content") "Error: No payload in response")))

          (display (string-append C-BLUE "\n[GAIA] Says: " C-RESET))
          (display response-text)
          (newline)

          ;; Check for completion signals
          (let ((final-sig (extract-final-signal response-text))
                (conf-val (extract-confidence response-text)))

            ;; Log interaction
            (let ((log-entry `(("session_id" . ,session-id)
                               ("input" . ,last-output)
                               ("response" . ,response-text)
                               ("timestamp" . ,(number->string (current-time)))
                               ("confidence" . ,(if conf-val conf-val "null"))
                               ("final_signal" . ,(if final-sig "true" "false")))))
              (let ((port (open-file "trajectories.jsonl" "a")))
                (display (scm->json log-entry) port)
                (newline port)
                (close-port port)))

            ;; Decision Logic: Delegation > Code > FINAL > Confidence > Text
            (let ((has-action (or (extract-delegation response-text) (extract-code response-text)))
                  (has-final (or final-sig (and conf-val (>= conf-val CONFIDENCE-THRESHOLD)))))
              (if (and has-action has-final)
                  (begin
                    (display (string-append C-RED "\n[GAIA] \u26a0 Halucination Detected: Mixed action and completion signal in one turn." C-RESET "\n"))
                    (let ((feedback "Error: You provided both an execution block (```scheme or ```delegate) and a completion signal (FINAL or high CONFIDENCE) in a single response. This is not allowed. Please provide ONLY the execution block, wait for the result, and then provide the completion signal in the next turn."))
                      (rlm-loop session-id feedback depth)))
                  (cond
                   ;; 1. Delegation (Action)
                   ((extract-delegation response-text) =>
                    (lambda (delegation)
                       (match delegation
                        (('delegate goal context)
                         (display (string-append C-YELLOW "\n[GAIA] Delegating sub-task..." C-RESET "\n"))
                         (let* ((sub-session-id (string-append session-id "-sub-" (number->string (random 1000))))
                                (initial-input (string-append "GOAL: " goal "\nCONTEXT: " context))
                                ;; Recursive call with NEW session ID
                                (sub-result (rlm-loop sub-session-id initial-input (+ depth 1))))

                           (display (string-append "\n[GAIA] Sub-task finished. Result: " sub-result "\n"))
                           ;; Continue in CURRENT session with the result
                           (rlm-loop session-id (string-append "Sub-agent execution finished. Result: " sub-result) depth)))
                        (_
                         (rlm-loop session-id "Error: Invalid delegation format. Use (delegate \"Goal\" \"Context\")" depth)))))

                   ;; 2. Scheme Execution (Action)
                   ((extract-code response-text) =>
                    (lambda (code)
                      (if (and code (> (string-length code) 0) (not (string=? code response-text)))
                          (begin
                            (display (string-append C-YELLOW "\n[GAIA] Executing Code..." C-RESET "\n"))
                            (match (guix-investigate code)
                              (('ok result)
                               (display "\n[GAIA] Result: ")
                               (display result)
                               (newline)

                               ;; Log execution (success)
                               (let ((exec-log `(("session_id" . ,session-id)
                                                 ("code" . ,code)
                                                 ("result" . ,result)
                                                 ("type" . "execution")
                                                 ("status" . "success"))))
                                   (let ((port (open-file "trajectories.jsonl" "a")))
                                       (display (scm->json exec-log) port)
                                       (newline port)
                                       (close-port port)))

                               ;; Recurse in SAME session with result
                               (rlm-loop session-id (string-append "The code execution result was: " result) depth))

                              (('error type msg)
                               (let ((feedback (handle-error type msg depth)))
                                 (display (string-append C-RED "\n[GAIA] Error: " feedback C-RESET "\n"))

                                 ;; Log execution (error)
                                 (let ((exec-log `(("session_id" . ,session-id)
                                                   ("code" . ,code)
                                                   ("result" . ,feedback)
                                                   ("type" . "execution")
                                                   ("status" . "error")
                                                   ("error_type" . ,(symbol->string type)))))
                                     (let ((port (open-file "trajectories.jsonl" "a")))
                                         (display (scm->json exec-log) port)
                                         (newline port)
                                         (close-port port)))

                                 (rlm-loop session-id feedback depth)))))

                          ;; Invalid code block
                          response-text)))

                   ;; 3. FINAL signal (Stop only if no action taken)
                   ((and final-sig (match final-sig (('final ans) ans) (('final-var var) var) (_ #f))) =>
                    (lambda (answer)
                      (display (string-append C-GREEN "\n[GAIA] \u2713 FINAL signal detected." C-RESET "\n"))
                      (if (equal? (car final-sig) 'final)
                          (display (string-append C-BOLD "[GAIA] Answer: " C-RESET answer "\n"))
                          (display (string-append C-BOLD "[GAIA] Answer stored in: " C-RESET answer "\n")))
                      answer))

                   ;; 4. High Confidence (Stop only if no action taken)
                   ((and conf-val (>= conf-val CONFIDENCE-THRESHOLD))
                    (display (string-append C-GREEN "\n[GAIA] \u2713 High confidence (" (number->string conf-val) "%) - stopping." C-RESET "\n"))
                    response-text)

                   ;; 5. Fallback (Text only)
                   (else
                    (display (string-append C-RED "\n[GAIA] \u26a0 No actionable output. Treating as final answer (unless low confidence)." C-RESET "\n"))
                    response-text)))))))))

(define (handle-command input session-id)
  "Parses and executes meta-commands or delegates to RLM."
  (cond
   ;; /exit
   ((string=? input "/exit")
    (display "Bye.\n")
    #f) ;; Return #f to stop loop

   ;; /help
   ((string=? input "/help")
    (display (string-append C-BOLD "Available commands:" C-RESET "\n"))
    (display "  /ask <query>   - One-shot question to AI (no RLM loop)\n")
    (display "  /eval <scheme> - Execute Scheme code locally\n")
    (display "  /models        - List available models and LoRA adapters\n")
    (display "  /model <name>  - Select a base model or LoRA adapter folder to load\n")
    (display "  /backend <name>- Select the backend to use (e.g. local, ollama)\n")
    (display "  /base-model <name>- Select the foundation model used for training\n")
    (display "  /train         - Manually trigger Fine Tuning (make learn) from dataset\n")
    (display "  /help          - Show this help\n")
    (display "  /exit          - Quit GAIA\n")
    (display "  <query>        - Start standard RLM investigation\n")
    #t)

   ;; /ask <query>
   ((string-prefix? "/ask " input)
    (let ((query (substring input 5)))
      (display "[Direct Question] Asking AI...\n")
      (let* ((response (chat-with-rai session-id query (get-config 'model) "You are a helpful Guile Scheme expert."))
             (payload (assoc-ref response "payload"))
             (content (if payload (assoc-ref payload "content") "Error No Payload")))
        (display "\nAI: ")
        (display content)
        (newline))
      #t))

   ;; /eval <scheme>
   ((string-prefix? "/eval " input)
    (let ((code (substring input 6)))
      (catch #t
        (lambda ()
          (display (eval-string code))
          (newline))
        (lambda (key . args)
          (display (format #f "Error: ~a ~a\n" key args))))
      #t))

   ;; /models
   ((string=? input "/models")
    (let ((models-alist (get-models)))
       (display (string-append C-BOLD "Available models (from RAI Registry):\n" C-RESET))
       (if (list? models-alist)
           (for-each (lambda (pair)
                       (let ((backend (car pair))
                             (model-vec (cdr pair)))
                         (display (string-append C-CYAN "  [" backend "]:\n" C-RESET))
                         (if (vector? model-vec)
                             (vector-for-each (lambda (i m) (display (string-append "    - " m "\n"))) model-vec)
                             (for-each (lambda (m) (display (string-append "    - " m "\n"))) model-vec))))
                     models-alist)
           (display (string-append C-RED "  No models found or unexpected response format.\n" C-RESET))))
    #t)

   ;; /model
   ((string=? input "/model")
    (display (string-append C-BOLD "Current model: " C-RESET (get-config 'model) "\n"))
    #t)

   ;; /model <name>
   ((string-prefix? "/model " input)
    (let ((new-model (substring input 7)))
       (set-config! 'model new-model)
       (display (string-append C-GREEN "Model hot-swapped for session to: " C-RESET new-model "\n")))
    #t)

   ;; /backend
   ((string=? input "/backend")
    (display (string-append C-BOLD "Current backend: " C-RESET (get-config 'backend) "\n"))
    #t)

   ;; /backend <name>
   ((string-prefix? "/backend " input)
    (let ((new-backend (substring input 9)))
       (set-config! 'backend new-backend)
       (display (string-append C-GREEN "Backend hot-swapped for session to: " C-RESET new-backend "\n")))
    #t)

   ;; /base-model
   ((string=? input "/base-model")
    (display (string-append C-BOLD "Current base model for training: " C-RESET (get-config 'base-model) "\n"))
    #t)

   ;; /base-model <name>
   ((string-prefix? "/base-model " input)
    (let ((new-base (substring input 12)))
       (set-config! 'base-model new-base)
       (display (string-append C-GREEN "Base model for training hot-swapped to: " C-RESET new-base "\n")))
    #t)

   ;; /train
   ((string=? input "/train")
    (display (string-append C-YELLOW "Triggering model training...\n" C-RESET))
    (let ((current-base (get-config 'base-model)))
      (setenv "GAIA_BASE_MODEL" current-base)
      (system* "make" "learn")
      (setenv "GAIA_BASE_MODEL" ""))
    #t)

   ;; Standard RLM Loop
   (else
    (rlm-loop session-id input 0)
    #t)))

(define (start-gaia . args)
  (activate-readline)
  (display (string-append C-BOLD C-GREEN "Initializing GAIA (GNU AI Assistant)..." C-RESET "\n"))

  (load-config)
  (display (format #f "Config Loaded:\n  Model: ~a~a~a\n  Backend: ~a\n  URL: ~a\n"
                   C-CYAN (get-config 'model) C-RESET
                   (get-config 'backend)
                   (get-config 'rai-url)))

  (display "Type '/help' for commands or enter a task.\n")

  (let ((session-id (string-append "gaia-"
                                   (number->string (current-time))
                                   "-"
                                   (number->string (random 10000)))))

    (display (string-append "Session ID: " session-id "\n"))

    (let loop ()
      (newline)
      (let ((input (readline (string-append "\x01" C-BOLD C-GREEN "\x02(GAIA) >\x01" C-RESET "\x02 "))))
        (cond
         ((eof-object? input) (newline))
         ((string=? input "") (loop))
         (else
          (add-history input) ;; Add to readline history
          (if (handle-command input session-id)
              (loop)
              #t)))))))
