(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (gaia core)
             (gaia executor)
             (gaia llm-client)
             (srfi srfi-64)
             (ice-9 match))

(test-begin "gaia-delegation")

;; Mock for chat-with-llm to simulate specific responses
(define call-count 0)

(define* (mock-chat-with-llm session-id input model prompt #:key (think #f) (history '()) (stream-callback #f))
  (set! call-count (+ call-count 1))
  (cond
    ;; First call: The "Core" agent decides to delegate
    ((= call-count 1)
     `(("payload" . (("content" . "I need to analyze this log file deeply.\n```delegate\n(delegate \"Analyze Log\" \"File: /var/log/syslog\")\n```")))))
    
    ;; Second call: The "Sub" agent (new session) works on the task
    ((= call-count 2)
     (if (string-contains session-id "-sub-")
         `(("payload" . (("content" . "I found 3 errors."))))
         `(("payload" . (("content" . "Error"))))))

    ;; Third call: Back to "Core" agent, receiving the result
    ((= call-count 3)
     `(("payload" . (("content" . "FINAL(The sub-agent found errors.)")))))

    (else
     `(("payload" . (("content" . "Stop")))))))

;; Override the real function with our mock in both modules
(let ((m-core (resolve-module '(gaia core)))
      (m-llm (resolve-module '(gaia llm-client))))
  (module-set! m-core 'chat-with-llm mock-chat-with-llm)
  (module-set! m-llm 'chat-with-llm mock-chat-with-llm))

(test-assert "Delegation flow works with correct return to parent and FINAL signal"
  (let* ((result-pair ((@@ (gaia core) rlm-loop) "test-session-1" "Start Task" 0 '()))
         (answer (car result-pair)))
    (and (string-contains answer "The sub-agent found errors.")
         (= call-count 3))))

(let* ((runner (test-runner-current))
       (fail (if runner (test-runner-fail-count runner) 0)))
  (test-end "gaia-delegation")
  (exit (if (> fail 0) 1 0)))
