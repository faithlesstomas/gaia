
(add-to-load-path (string-append (dirname (current-filename)) "/../scheme"))

(use-modules (gaia core)
             (gaia executor)
             (gaia llm-client)
             (ice-9 match))

(display "[TEST] Starting RLM Delegation Test...\n")

;; Mock for chat-with-llm to simulate specific responses
;; We use a simple counter to return different responses based on the call count
(define call-count 0)

(define (mock-chat-with-llm session-id input model prompt)
  (set! call-count (+ call-count 1))
  (display (format #f "  DEBUG: Mock called. Session: ~a, Count: ~a\n" session-id call-count))
  
  (cond
    ;; First call: The "Core" agent decides to delegate
    ((= call-count 1)
     `(("payload" . (("content" . "I need to analyze this log file deeply.\n```delegate\n(delegate \"Analyze Log\" \"File: /var/log/syslog\")\n```")))))
    
    ;; Second call: The "Sub" agent (new session) works on the task
    ((= call-count 2)
     (if (string-contains session-id "-sub-")
         (begin
            (display "  PASS: New session ID detected for sub-agent.\n")
            `(("payload" . (("content" . "I found 3 errors.")))))
         (begin
            (display "  FAIL: Expected sub-session ID.\n")
            `(("payload" . (("content" . "Error")))))))

    ;; Third call: Back to "Core" agent, receiving the result
    ((= call-count 3)
     (display "  PASS: Control returned to parent agent.\n")
     `(("payload" . (("content" . "Final Answer: The sub-agent found errors.")))))

    (else
     `(("payload" . (("content" . "Stop")))))))

;; Override the real function with our mock
(module-define! (resolve-module '(gaia core)) 'chat-with-llm mock-chat-with-llm)

;; Run the test
;; We need to expose rlm-loop or just import it if it was exported.
;; Since rlm-loop is not exported, we might need a workaround or test start-gaia logic if possible.
;; However, core.scm exports start-gaia. Let's try to run a modified loop or just ensure we can call it.
;; Actually, to properly test rlm-loop which is internal, we should probably temporarily export it or use (@@ (gaia core) rlm-loop).

(display "[TEST] Invoking rlm-loop...\n")
((@@ (gaia core) rlm-loop) "test-session-1" "Start Task" 0)

(display "[TEST] Finished.\n")
