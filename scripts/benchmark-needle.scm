(add-to-load-path (string-append (dirname (current-filename)) "/../scheme"))

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
  (display (format #f "[BENCHMARK] Config:\n  Model:   ~a\n  Backend: ~a\n  URL:     ~a\n"
                   (get-config 'model)
                   (get-config 'backend)
                   (get-config 'rai-url)))

  (generate-haystack)
  (display "Starting RLM Benchmark (End-to-End via rlm-loop)...\n")
  (display "[BENCHMARK] Task: Find secret key in haystack.txt.\n")

  (let ((session-id (string-append "bench-" (number->string (current-time)) "-" (number->string (random 1000000000))))
        (initial-prompt (format #f "There is a file named '~a' in the current directory. It contains a secret key that starts with 'GAIA_SECRET_KEY_'. Find it and return it using the FINAL() signal." HAYSTACK-FILE)))

    ;; Run RLM Loop
    (let ((result (rlm-loop session-id initial-prompt 0)))
      (display (format #f "\n[BENCHMARK] RLM returned: ~a\n" result))

      (if (string-contains result NEEDLE)
          (display "\n[BENCHMARK] SUCCESS! Found needle.\n")
          (display "\n[BENCHMARK] FAILURE. Needle not found in result.\n"))))

  ;; Cleanup
  (if (file-exists? HAYSTACK-FILE)
      (delete-file HAYSTACK-FILE)))

(run-benchmark)
