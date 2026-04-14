(add-to-load-path (string-append (dirname (current-filename)) "/../scheme"))

(use-modules (gaia core)
             (gaia config)
             (ice-9 ftw)
             (ice-9 format))

;; --- Sanity Check: RLM Pipeline ---
;;
;; This is a DETERMINISTIC sanity check of the full RLM pipeline.
;; It does NOT test model quality — it tests that the mechanism works:
;;   1. Connection to LLM API
;;   2. System prompt is respected
;;   3. Model generates a Scheme code block
;;   4. Executor runs code in container
;;   5. Model detects result and returns FINAL()
;;   6. rlm-loop correctly parses the FINAL() signal
;;
;; Task: Count .scm files in scheme/gaia/ directory.
;; Expected: deterministic integer, computed locally and verified against model's answer.

(define TASK-DIR "scheme/gaia")

(define (count-scm-files dir)
  "Count .scm files in directory using local Guile (no LLM)."
  (let ((entries (scandir dir (lambda (f) (string-suffix? ".scm" f)))))
    (if entries (length entries) 0)))

(define (run-sanity)
  (load-config)
  (display (format #f "[SANITY] Config:\n  Model:   ~a\n  URL:     ~a\n"
                   (get-config 'model)
                   (get-config 'llm-url)))

  (let* ((expected (count-scm-files TASK-DIR))
         (session-id (string-append "sanity-"
                                    (number->string (current-time))
                                    "-"
                                    (number->string (random 1000000000))))
         (prompt (format #f
                   "Count the number of .scm files in the '~a' directory using Scheme code and available tools. Return the integer count using FINAL(N)."
                   TASK-DIR)))

    (display (format #f "[SANITY] Expected count: ~a\n" expected))
    (display "[SANITY] Starting RLM pipeline sanity check...\n")

    (let ((result (rlm-loop session-id prompt 0)))
      (display (format #f "\n[SANITY] RLM returned: ~a\n" result))

      (if (string-contains result (number->string expected))
          (begin
            (display "\n[SANITY] ✓ SUCCESS! Pipeline works correctly.\n")
            (exit 0))
          (begin
            (display (format #f "\n[SANITY] ✗ FAILURE! Expected '~a' in result.\n" expected))
            (exit 1))))))

(run-sanity)
