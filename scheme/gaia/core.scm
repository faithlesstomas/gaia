(define-module (gaia core)
  #:use-module (gaia rai-client)
  #:use-module (gaia executor)
  #:use-module (gaia utils)
  #:use-module (ice-9 match)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 readline)
  #:use-module (ice-9 rdelim)
  #:export (start-gaia SYSTEM_PROMPT extract-code extract-final-signal extract-confidence rlm-loop))

(define MODEL "ministral-3:3b")


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
        (display (string-append "\n[GAIA] Thinking (Depth " (number->string depth) ")...\n"))
        (let* ((response (chat-with-rai session-id last-output MODEL SYSTEM_PROMPT))
               (payload (assoc-ref response "payload"))
               (response-text (if payload (assoc-ref payload "content") "Error: No payload in response")))

          (display "\n[GAIA] Says: ")
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

            ;; Decision Logic: FINAL > Confidence > Delegation > Code > Text
            (cond
             ;; 1. FINAL signal
             ((and final-sig (match final-sig (('final ans) ans) (('final-var var) var) (_ #f))) =>
              (lambda (answer)
                (display "\n[GAIA] \u2713 FINAL signal detected.\n")
                (if (equal? (car final-sig) 'final)
                    (display (string-append "[GAIA] Answer: " answer "\n"))
                    (display (string-append "[GAIA] Answer stored in: " answer "\n")))
                answer))
             
             ;; 2. High Confidence
             ((and conf-val (>= conf-val CONFIDENCE-THRESHOLD))
              (display (string-append "\n[GAIA] \u2713 High confidence (" (number->string conf-val) "%) - stopping.\n"))
              response-text)

             ;; 3. Delegation
             ((extract-delegation response-text) =>
              (lambda (delegation)
                 (match delegation
                  (('delegate goal context)
                   (display "\n[GAIA] Delegating sub-task...\n")
                   (let* ((sub-session-id (string-append session-id "-sub-" (number->string (random 1000))))
                          (initial-input (string-append "GOAL: " goal "\nCONTEXT: " context))
                          ;; Recursive call with NEW session ID
                          (sub-result (rlm-loop sub-session-id initial-input (+ depth 1))))

                     (display (string-append "\n[GAIA] Sub-task finished. Result: " sub-result "\n"))
                     ;; Continue in CURRENT session with the result
                     (rlm-loop session-id (string-append "Sub-agent execution finished. Result: " sub-result) depth)))
                  (_
                   (rlm-loop session-id "Error: Invalid delegation format. Use (delegate \"Goal\" \"Context\")" depth)))))

             ;; 4. Scheme Execution
             ((extract-code response-text) =>
              (lambda (code)
                (if (and code (> (string-length code) 0) (not (string=? code response-text)))
                    (begin
                      (display "\n[GAIA] Executing Code...\n")
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
                           (display (string-append "\n[GAIA] Error: " feedback "\n"))
                           
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
             
             ;; 5. Fallback (Text only)
             (else 
              (display "\n[GAIA] \u26a0 No actionable output. Treating as final answer (unless low confidence).\n")
              response-text)))))))

(define (handle-command input session-id)
  "Parses and executes meta-commands or delegates to RLM."
  (cond
   ;; ,exit
   ((string=? input ",exit")
    (display "Bye.\n")
    #f) ;; Return #f to stop loop
   
   ;; ,help
   ((string=? input ",help")
    (display "Available commands:\n")
    (display "  ,ask <query>   - One-shot question to AI (no RLM loop)\n")
    (display "  ,eval <scheme> - Execute Scheme code locally\n")
    (display "  ,help          - Show this help\n")
    (display "  ,exit          - Quit GAIA\n")
    (display "  <query>        - Start standard RLM investigation\n")
    #t)

   ;; ,ask <query>
   ((string-prefix? ",ask " input)
    (let ((query (substring input 5)))
      (display "[Direct Question] Asking AI...\n")
      (let* ((response (chat-with-rai session-id query MODEL "You are a helpful Guile Scheme expert."))
             (payload (assoc-ref response "payload"))
             (content (if payload (assoc-ref payload "content") "Error No Payload")))
        (display "\nAI: ")
        (display content)
        (newline))
      #t))

   ;; ,eval <scheme>
   ((string-prefix? ",eval " input)
    (let ((code (substring input 6)))
      (catch #t
        (lambda ()
          (display (eval-string code))
          (newline))
        (lambda (key . args) 
          (display (format #f "Error: ~a ~a\n" key args))))
      #t))

   ;; Standard RLM Loop
   (else
    (rlm-loop session-id input 0)
    #t)))

(define (start-gaia . args)
  (activate-readline)
  (display "Initializing GAIA (GNU AI Assistant)...\n")
  (display "Type ',help' for commands or enter a task.\n")
  
  (let ((session-id (string-append "gaia-"
                                   (number->string (current-time))
                                   "-"
                                   (number->string (random 10000)))))

    (display (string-append "Session ID: " session-id "\n"))
    
    (let loop ()
      (display "\n[GAIA]> ")
      (let ((input (read-line)))
        (cond
         ((eof-object? input) (newline))
         ((string=? input "") (loop))
         (else
          (if (handle-command input session-id)
              (loop)
              #t)))))))
