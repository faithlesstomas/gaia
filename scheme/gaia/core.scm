(define-module (gaia core)
  #:use-module (gaia rai-client)
  #:use-module (gaia executor)
  #:use-module (gaia utils)
  #:use-module (gaia utils)
  #:use-module (ice-9 match)
  #:use-module (ice-9 readline)
  #:use-module (ice-9 rdelim)
  #:export (start-gaia))

(define SYSTEM_PROMPT
  "You are GAIA, a GNU AI Assistant operating within a Guix System.
Your goal is to investigate the system and answer user queries by executing Guile Scheme code.
You have access to a `guix-investigate` tool which runs code in a sandbox.
To use it, output ONLY the Scheme code enclosed in a block like:
```scheme
(display \"hello\")
```
Do not provide explanations, just the code. The result of the code will be returned to you.")

(define (extract-code response)
  "Extracts Scheme code from the LLM response (markdown code block)."
  (let ((str (if (string? response) response (scm->json response))))
    ;; Simple regex-like search (Guile's regex is POSIX)
    ;; For now, just look for ```scheme ... ``` or return the whole string if it looks like code
    (if (string-contains str "```scheme")
        (let* ((start (+ (string-contains str "```scheme") 9))
               (end (string-contains str "```" start)))
          (substring str start end))
        str)))

(define (rlm-loop session-id last-output)
  (display "\n[GAIA] Thinking...\n")
  (let* ((response (chat-with-rai session-id last-output "gemma3:4b"))
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
              (rlm-loop session-id (string-append "The code execution result was: " result))))
          (display "\n[GAIA] Awaiting further instructions.\n")))))

(define (start-gaia)
  (activate-readline)
  (display "Initializing GAIA...\n")
  ;; Create a new session or use a fixed one for testing
  (let ((session-id "gaia-session-1"))
    ;; (create-agent "gaia-main" "gemma3:4b" SYSTEM_PROMPT) ;; Ideally create dynamic agent
    
    (display "GAIA Ready. Type your query (or 'exit'): > ")
    (let loop ()
      (let ((input (read-line)))
        (cond
         ((eof-object? input) (newline))
         ((string=? input "exit") (display "Bye.\n"))
         (else
          (rlm-loop session-id input)
          (display "\n> ")
          (loop)))))))
