(add-to-load-path (string-append (dirname (current-filename)) "/../scheme"))

(use-modules (gaia core)
             (gaia executor)
             (gaia rai-client)
             (ice-9 rdelim)
             (ice-9 format))

(define HAYSTACK-FILE "haystack.txt")
(define NEEDLE "GAIA_SECRET_KEY_999")
(define FILE-SIZE-MB 10)

(define (generate-haystack)
  (display (format #f "Generating ~aMB haystack...\n" FILE-SIZE-MB))
  (with-output-to-file HAYSTACK-FILE
    (lambda ()
      ;; Write random data
      (do ((i 0 (+ i 1)))
          ((> i (* FILE-SIZE-MB 1024)))
        (display "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ")
        (newline))
      ;; Insert needle at the end
      (display (format #f "\nTHE SECRET IS: ~a\n" NEEDLE))
      (display "More filler content...\n"))))


(define MAX-RETRIES 50) ;; Increased retries for harder task

(define (benchmark-loop session-id history retries-left)
  (if (= retries-left 0)
      (begin
        (display "\n[BENCHMARK] Max retries reached. FAILED.\n")
        #f)
      (begin
        (display (format #f "\n[BENCHMARK] Step ~a (Retries left: ~a). Thinking...\n" (- MAX-RETRIES retries-left) retries-left))

        ;; Construct valid chat history for RAI
        (cond
         ((string? history) ;; Initial prompt
          (let* ((response (chat-with-rai session-id history "gemma3:4b" SYSTEM_PROMPT))
                 (response-text (or (assoc-ref (assoc-ref response "payload") "content") "Error")))
            (process-response session-id response-text retries-left)))

         (else ;; Recursive step
          (let* ((response (chat-with-rai session-id history "gemma3:4b" SYSTEM_PROMPT))
                 (response-text (or (assoc-ref (assoc-ref response "payload") "content") "Error")))
            (process-response session-id response-text retries-left)))))))

(define (process-response session-id response-text retries-left)
  (display (format #f "\n[RAI] says:\n~a\n" response-text))

  (let ((code (extract-code response-text)))
    (if (string? code)
        (begin
          (display "\n[BENCHMARK] Executing Code...\n")
          (let ((result (guix-investigate code)))
            (display (format #f "\n[BENCHMARK] Result:\n~a\n" result))

            (if (string-contains result "Error:")
                ;; RECURSION WITH FEEDBACK
                (benchmark-loop session-id (string-append "The code executed with error:\n" result "\nPlease correct the code and try again.") (- retries-left 1))
                ;; CHECK SUCCESS OR TEXT RESULT
                (if (string-contains result NEEDLE)
                    (begin
                      (display (format #f "\n[BENCHMARK] SUCCESS! Found needle: ~a\n" result))
                      #t)
                    ;; If no error but no needle, simply give result feedback and ask to proceed
                    (benchmark-loop session-id (string-append "The code executed successfully. The output was:\n" result "\nDoes this solve the task? If not, proceed with the next step.") (- retries-left 1))))))

        ;; No code found
        (begin
            (display "\n[BENCHMARK] No code found in response.\n")
            ;; Just feed the text back as if it's a conversation step, or prompt for code if it seems stuck.
            ;; For benchmark, we nudge it to write code if it just talks.
            (benchmark-loop session-id "Please proceed with the investigation by writing Scheme code." (- retries-left 1))))))

(define (run-benchmark)
  (generate-haystack)
  (display "Haystack generated. Starting RLM Benchmark (End-to-End)...\n")

  (display "[BENCHMARK] Task: Find secret key in haystack.txt using LLM.\n")

  (let ((session-id (string-append "bench-" (number->string (random 10000))))
        ;; SIMPLIFIED PROMPT: Just the goal.
        (initial-prompt (format #f "There is a file named '~a' in the current directory. It contains a secret key that starts with 'GAIA_SECRET_KEY_'. Find it and output the full key." HAYSTACK-FILE)))

    (benchmark-loop session-id initial-prompt MAX-RETRIES)

  (delete-file HAYSTACK-FILE)))

(run-benchmark)
