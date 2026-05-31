(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (gaia core)
             (gaia config)
             (gaia executor) ;; for guix-investigate if needed, but rlm-loop handles it
             (ice-9 rdelim)
             (ice-9 format)
             (ice-9 match))

(define HAYSTACK-FILE "haystack.txt")
(define NEEDLE "GAIA_SECRET_KEY_999")
(define FILE-SIZE-MB (string->number (or (getenv "BENCHMARK_SIZE_MB") "10")))

(define (generate-haystack)
  (display (format #f "Generating ~aMB haystack...\n" FILE-SIZE-MB))
  (with-output-to-file HAYSTACK-FILE
    (lambda ()
      ;; Write random data
      (do ((i 0 (+ i 1)))
          ((> i (* FILE-SIZE-MB 100))) ;; Smaller loops for speed, larger chunks
        (display "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. ")
        (newline))
      ;; Insert needle at the end
      (display (format #f "\nTHE SECRET IS: ~a\n" NEEDLE))
      (display "More filler content...\n")))
  (display "Haystack generated.\n"))

(define (run-benchmark)
  ;; Load config from environment variables
  (load-config)
  (display (format #f "[BENCHMARK] Config:\n  Model:   ~a\n  URL:     ~a\n"
                   (get-config 'model)
                   (get-config 'llm-url)))

  (generate-haystack)
  (display "Starting RLM Benchmark (End-to-End via rlm-loop)...\n")
  (display "[BENCHMARK] Task: Find secret key in haystack.txt.\n")

  (let ((session-id (string-append "bench-" (number->string (current-time)) "-" (number->string (random 1000000000))))
        (initial-prompt (format #f "There is a large file named '~a' in the current directory. It is ~aMB and contains a secret key hidden somewhere in the text. The key starts with 'GAIA_SECRET_KEY_'. Use search-file to find the line containing it, extract the key, and return it using FINAL()." HAYSTACK-FILE FILE-SIZE-MB)))

    ;; Run RLM Loop
    (let ((result (car (rlm-loop session-id initial-prompt 0 '()))))
      (display (format #f "\n[BENCHMARK] RLM returned: ~a\n" result))

      ;; Check if the result contains the needle
      ;; Distinguish between proper FINAL() usage and accidental inclusion in prose
      (let ((final-sig (extract-final-signal result)))
        (cond
         ;; Best case: FINAL() signal contains the needle
         ((and final-sig
               (match final-sig
                 (('final ans) (string-contains ans NEEDLE))
                 (('final-var var) (string-contains var NEEDLE))
                 (_ #f)))
          (display "\n[BENCHMARK] ✓ SUCCESS! Found needle via FINAL() signal.\n"))

         ;; Acceptable: needle is somewhere in the raw output
         ((string-contains result NEEDLE)
          (display "\n[BENCHMARK] ⚠ PARTIAL SUCCESS: Needle found in output, but not via FINAL().\n"))

         ;; Failure
         (else
          (display "\n[BENCHMARK] ✗ FAILURE. Needle not found in result.\n"))))))

  ;; Cleanup
  (if (file-exists? HAYSTACK-FILE)
      (delete-file HAYSTACK-FILE)))

(run-benchmark)
