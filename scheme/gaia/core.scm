(define-module (gaia core)
  #:use-module (gaia rai-client)
  #:use-module (gaia executor)
  #:use-module (gaia utils)
  #:use-module (gaia utils)
  #:use-module (ice-9 match)
  #:use-module (ice-9 readline)
  #:use-module (ice-9 rdelim)
  #:export (start-gaia SYSTEM_PROMPT extract-code))

(define MODEL "ministral-3:3b")



(define SYSTEM_PROMPT
  "# ROLE
You are GAIA (GNU AI Assistant), an advanced system operator powered by the RAI (Rich AI) server. Your primary goal is to solve technical tasks within a GNU Guix environment using the Recursive Language Model (RLM) paradigm.

# ENVIRONMENT & TOOLS
- Operating System: GNU Guix.
- Primary Language: Guile Scheme (S-expressions).
- Execution Method: You do not read large files directly. Instead, you generate Guile Scheme code that runs inside isolated 'guix shell --container' environments to investigate the system.

# RLM OPERATIONAL RULES
1. INVESTIGATE, DON'T READ: If a task involves large files (logs, source code, system state), do NOT ask the user to provide the text. Write a Guile script to explore the file (e.g., using `mmap`, `stat`, or `ice-9 rdelim`).
2. PROGRAMMATIC EXTRACTION: Your code should find and return only the relevant fragments of data needed for the next step.
3. RECURSION: If the result of your code execution shows that the data is still too complex, propose the next specific sub-task. The GAIA system will call you recursively with the new context.
4. CODE BLOCKS: Always wrap your Scheme code in triple backticks: ```scheme ... ```.

# GUILE SCHEME GUIDELINES
- Use functional programming patterns.
- Always include necessary modules, e.g., `(use-modules (ice-9 rdelim) (ice-9 regex) (guix profiles))`.
- Focus on safety and precision. Ensure your S-expressions are well-formed and balanced.

# EXAMPLE TASK FLOW
User: \"Find all 'Permission Denied' errors in /var/log/messages and summarize the affected services.\"
GAIA Thinking:
1. Check file size using (stat).
2. If large, write a script to grep for \"Permission Denied\".
3. Return the unique service names found.
4. If there are many errors, spawn a sub-task for each unique service.")

(define (extract-code response)
  "Extracts Scheme code from the LLM response (markdown code block)."
  (let ((str (if (string? response) response (scm->json response))))
    ;; Simple regex-like search (Guile's regex is POSIX)
    ;; For now, just look for ```scheme ... ``` or return the whole string if it looks like code
    (if (string-contains str "```scheme")
        (let* ((start (+ (string-contains str "```scheme") 9))
               (end (string-contains str "```" start)))
          (substring str start end))
        #f)))

(define MAX-RECURSION-DEPTH 15)

(define (rlm-loop session-id last-output depth)
  (if (> depth MAX-RECURSION-DEPTH)
      (display "\n[GAIA] Max recursion depth reached. Stopping loop.\n")
      (begin
        (display "\n[GAIA] Thinking...\n")
        (let* ((response (chat-with-rai session-id last-output MODEL SYSTEM_PROMPT))
               (payload (assoc-ref response "payload"))
               (response-text (if payload (assoc-ref payload "content") "Error: No payload in response")))

          (display "\n[GAIA] Says: ")
          (display response-text)
          (newline)

          ;; Log interaction
          (let ((log-entry `(("session_id" . ,session-id)
                             ("input" . ,last-output)
                             ("response" . ,response-text)
                             ("timestamp" . ,(number->string (current-time))))))
              (let ((port (open-file "trajectories.jsonl" "a")))
                  (display (scm->json log-entry) port)
                  (newline port)
                  (close-port port)))

          (let ((code (extract-code response-text)))
            (if (and code (> (string-length code) 0) (not (string=? code response-text)))
                (begin
                  (display "\n[GAIA] Executing Code...\n")
                  (let ((result (guix-investigate code)))
                    (display "\n[GAIA] Result: ")
                    (display result)
                    (newline)

                    ;; Log execution
                    (let ((exec-log `(("session_id" . ,session-id)
                                      ("code" . ,code)
                                      ("result" . ,result)
                                      ("type" . "execution"))))
                      (let ((port (open-file "trajectories.jsonl" "a")))
                          (display (scm->json exec-log) port)
                          (newline port)
                          (close-port port)))

                    ;; Recurse with result
                    (rlm-loop session-id (string-append "The code execution result was: " result) (+ depth 1))))
                (display "\n[GAIA] Awaiting further instructions.\n")))))))

(define (start-gaia)
  (activate-readline)
  (display "Initializing GAIA...\n")
  ;; Generate a dynamic session ID using rudimentary randomness
  (let ((session-id (string-append "gaia-"
                                   (number->string (current-time))
                                   "-"
                                   (number->string (random 10000)))))

    (display (string-append "Session ID: " session-id "\n"))
    (display "GAIA Ready. Type your query (or 'exit'): > ")
    (let loop ()
      (let ((input (read-line)))
        (cond
         ((eof-object? input) (newline))
         ((string=? input "exit") (display "Bye.\n"))
         (else
          (rlm-loop session-id input 0)
          (display "\n> ")
          (loop)))))))
