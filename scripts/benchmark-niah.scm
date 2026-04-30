;;; benchmark-niah.scm — Proper S-NIAH Benchmark (paper-aligned)
;;;
;;; Tests the core RLM mechanism: the model receives a massive context as
;;; a variable in the REPL, must chunk it, and use `llm_query` per chunk
;;; to find a hidden needle. This tests true recursion — search-file
;;; won't help because the data is in memory, not on disk.
;;;
;;; Paper reference: "Following the single needle-in-the-haystack task in
;;; RULER, we consider tasks that require finding a specific phrase or
;;; number in a large set of unrelated text."

(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (gaia core)
             (gaia config)
             (gaia rlm-env)
             (gaia llm-client)
             (ice-9 format)
             (ice-9 match))

;; --- Configuration ---

(define NEEDLE "GAIA_SECRET_KEY_42X7")
;; Default 64KB — safe for 4K context window models (small chunks).
;; For larger context models, set BENCHMARK_SIZE_KB=512 or higher.
(define CONTEXT-SIZE-KB (string->number (or (getenv "BENCHMARK_SIZE_KB") "64")))
(define FILLER-LINE "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.\n")

;; --- Generate haystack as a string (NOT a file) ---

(define (generate-haystack-string)
  "Generates a large string with a needle hidden somewhere in the middle."
  (let* ((filler-line-len (string-length FILLER-LINE))
         (target-chars (* CONTEXT-SIZE-KB 1024))
         (num-lines (quotient target-chars filler-line-len))
         ;; Insert needle roughly in the middle third
         (needle-pos (+ (quotient num-lines 3)
                        (random (quotient num-lines 3))))
         (needle-line (string-append "THE SECRET IS: " NEEDLE "\n"))
         (port (open-output-string)))
    (do ((i 0 (+ i 1)))
        ((= i num-lines))
      (if (= i needle-pos)
          (display needle-line port)
          (display FILLER-LINE port)))
    (get-output-string port)))

;; --- Build the prompt using string-append (avoids ~a format conflicts) ---

(define (build-prompt haystack-len)
  (string-append
    "The variable `context` is ALREADY LOADED in your REPL environment with "
    (number->string haystack-len)
    " characters of text.
`context` is a Guile string variable. DO NOT use read-file. It is already in memory.

Hidden somewhere in this text is a line containing a secret key starting with 'GAIA_SECRET_KEY_'.

IMPORTANT: The sub-LLM has a SMALL context window (~3000 chars max per query). Use small chunks.

Step 1 — check the size:
```repl
(display (string-length context))
```

Step 2 — chunk and search using llm-query with SMALL chunks:
```repl
(define chunk-size 2000)
(define total (string-length context))
(let loop ((start 0))
  (when (< start total)
    (let* ((end (min (+ start chunk-size) total))
           (chunk (substring context start end))
           (answer (llm-query (string-append \"Does this text contain a line with GAIA_SECRET_KEY_? Answer ONLY the key or NOT_FOUND:\\n\" chunk))))
      (display (string-append \"Chunk \" (number->string start) \": \" answer \"\\n\"))
      (if (string-contains answer \"GAIA_SECRET_KEY_\")
          (display (string-append \"FOUND IT: \" answer \"\\n\"))
          (loop (+ start chunk-size))))))
```

Step 3 — when found, return with FINAL(the_key)."))

;; --- Run benchmark ---

(define (run-benchmark)
  (load-config)
  (display (format #f "[S-NIAH] Config:\n  Model:   ~a\n  Context: ~aKB\n  Needle:  ~a\n"
                   (get-config 'model)
                   CONTEXT-SIZE-KB
                   NEEDLE))

  ;; Generate haystack as a string
  (display "[S-NIAH] Generating haystack string...\n")
  (let* ((haystack (generate-haystack-string))
         (haystack-len (string-length haystack)))
    (display (format #f "[S-NIAH] Haystack: ~a chars (~aKB)\n" haystack-len (quotient haystack-len 1024)))

    ;; Create RLM environment with context loaded as a variable
    (let ((env (make-rlm-env))
          (session-id (string-append "niah-" (number->string (current-time))
                                     "-" (number->string (random 1000000000)))))

      ;; Inject llm_query — sub-LM calls for recursive chunking
      ;; Minimal system prompt to save tokens in the 4K context window
      (rlm-inject! env 'llm-query
        (lambda (prompt)
          (let* ((sub-session (string-append session-id "-sub-" (number->string (random 1000))))
                 (response (chat-with-llm sub-session prompt (get-config 'model)
                             "You are a text search tool. When given text, look for lines containing GAIA_SECRET_KEY_. If found, respond with ONLY the key (e.g. GAIA_SECRET_KEY_42X7). If not found, respond with exactly: NOT_FOUND"))
                 (payload (assoc-ref response "payload")))
            (if payload
                (assoc-ref payload "content")
                "NOT_FOUND"))))

      ;; Inject the haystack as `context`
      (rlm-inject! env 'context haystack)

      ;; Build prompt safely
      (let ((prompt (build-prompt haystack-len)))

        (display (format #f "[S-NIAH] Starting RLM benchmark...\n[S-NIAH] Prompt length: ~a chars\n" (string-length prompt)))

        ;; Run RLM loop with pre-configured environment
        (let ((result (rlm-loop session-id prompt 0 '() env)))
          (display (format #f "\n[S-NIAH] RLM returned: ~a\n" result))

          ;; Evaluate result
          (let ((final-sig (extract-final-signal result)))
            (cond
             ;; Best: FINAL() contains the needle (checked via direct match as rlm-loop returns unwrapped answer)
             ((string-contains result NEEDLE)
              (display "\n[S-NIAH] ✓ SUCCESS! Found needle via recursive chunking.\n"))

             ;; Failure
             (else
              (display "\n[S-NIAH] ✗ FAILURE. Needle not found.\n")))))))))

(run-benchmark)
