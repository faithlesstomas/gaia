(define-module (gaia core)
  #:use-module (gaia rai-client)
  #:use-module (gaia executor)
  #:use-module (gaia rlm-env)
  #:use-module (gaia utils)
  #:use-module (ice-9 match)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 readline)
  #:use-module (ice-9 rdelim)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (srfi srfi-43)
  #:use-module (gaia config)
  #:export (start-gaia SYSTEM_PROMPT extract-code extract-final-signal extract-confidence rlm-loop))




(define C-RESET "\x1b[0m")
(define C-BOLD "\x1b[1m")
(define C-RED "\x1b[31m")
(define C-GREEN "\x1b[32m")
(define C-YELLOW "\x1b[33m")
(define C-BLUE "\x1b[34m")
(define C-CYAN "\x1b[36m")
(define C-GREY "\x1b[90m")

(define SYSTEM_PROMPT
  "# ROLE
You are GAIA (GNU AI Assistant), a system operator implementing the Recursive Language Model (RLM) paradigm.
You solve complex tasks by writing and executing GNU Guile Scheme code in a persistent REPL environment.

# EXECUTION ENVIRONMENT
- Language: GNU Guile Scheme (NOT Racket, NOT Chicken Scheme).
- CRITICAL: Use `(use-modules ...)` for imports. NEVER use `require` — that is Racket syntax!
- Your code runs in a persistent REPL: variables and functions you define in one step are available in the next.
- Output from `display`, `write`, `format` is captured and returned to you.

# PRE-LOADED MODULES (already available, no need to import)
- `(srfi srfi-1)` — List library: `filter`, `fold`, `any`, `every`, `partition`, etc.
- `(srfi srfi-13)` — String library: `string-contains`, `string-prefix?`, `string-suffix?`, `string-trim`, etc.
- `(ice-9 regex)` — Regex: `string-match`, `match:substring`, etc.
- `(ice-9 match)` — Pattern matching: `(match expr ((pattern) body) ...)`.
- `(ice-9 rdelim)` — I/O: `read-line`, `read-string`.
- `(ice-9 ftw)` — File traversal: `scandir`, `file-system-fold`.

# AVAILABLE TOOLS (from `(gaia tools)`, already loaded)
- `(list-files path)` — Returns list of files in directory.
- `(read-file path)` — Returns file content as string. WARNING: for large files, do NOT display the output! Use search-file instead.
- `(write-file path content)` — Writes string to file.
- `(file-info path)` — Returns file metadata (size, type, permissions).
- `(search-file pattern path-to-file)` — Grep for PATTERN in FILE. Example: `(search-file \"SECRET\" \"haystack.txt\")`. Returns matching lines as a string.
- `(run-sed expression path)` — Runs sed expression on file (stdout only).
- `(run-awk program path)` — Runs awk program on file.

# YOUR REPL ENVIRONMENT IS PRE-INITIALIZED WITH:
1. A `context` variable — it is ALREADY DEFINED and contains your task data as a string.
   Access it directly: `(string-length context)`, `(substring context 0 100)`, etc.
   DO NOT try to load it from a file. DO NOT call read-file to get context. It is a VARIABLE, already in memory.
2. `(llm-query prompt)` — Query a sub-LLM with the given prompt string. Returns its text response.
   Use for recursive reasoning: chunk context, query sub-LLMs per chunk, aggregate results.
3. String helpers (already available — no imports needed):
   - `(string-after str needle)` → substring after needle, or #f. Example: `(string-after \"KEY=hello\" \"KEY=\")` → `\"hello\"`
   - `(string-before str needle)` → substring before needle, or #f
   - `(extract-match str regex)` → first regex match/capture group, or #f
   - `(split-string str delim)` → splits string by string delimiter. Example: `(split-string \"a::b\" \"::\")` → `(\"a\" \"b\")`

# GUILE-SPECIFIC WARNINGS
- CRITICAL: Guile's built-in `string-split` takes a CHARACTER, not a string! Use `#\\space` not `\" \"`.
  Example: `(string-split \"hello world\" #\\space)` → `(\"hello\" \"world\")`
  For string delimiters, use the injected `split-string` instead.
- Use `string-contains` to find substrings: `(string-contains \"hello world\" \"world\")` → index or #f.
- Use `string-after`/`string-before` for simple extraction tasks.


# HOW TO WRITE CODE
Wrap your Guile Scheme code in a ```repl code block:
```repl
(define files (list-files \"/workspace\"))
(display (length files))
```

The system will execute your code and return the output. You can then reason about the output and write more code.

# COMPLETION SIGNALS
When you have solved the task COMPLETELY, use ONE of these signals:
- `FINAL(answer)` — For direct text answers. Example: `FINAL(The file contains 42 errors)`
- `FINAL_VAR(variable_name)` — For answers stored in a variable from code execution.

After each step, rate your confidence:
- `CONFIDENCE(score)` — 0-100%. If >= 95%, the system stops automatically.

# CRITICAL RULES
1. NEVER put FINAL() or FINAL_VAR() in the same response as a ```repl code block!
   Write code → WAIT for results → then provide FINAL() in NEXT response.
   Note: CONFIDENCE() alongside code is OK and expected.
2. Use the pre-loaded tools and modules. Do NOT try to import them again.
3. Think step by step. Use `display` or `write` to inspect intermediate results.
4. For large data: use `search-file` to find relevant lines. NEVER try to display entire large files.

# EXAMPLE TASK FLOW
User: \"Count .scm files in scheme/gaia/\"
Step 1 (GAIA writes code):
```repl
(define files (list-files \"scheme/gaia\"))
(define scm-files (filter (lambda (f) (string-suffix? \".scm\" f)) files))
(display (length scm-files))
```
Step 2 (System returns): \"8\"
Step 3 (GAIA answers):
The directory contains 8 .scm files.
FINAL(8)
CONFIDENCE(100)
")

(define (extract-code response)
  "Extracts Scheme code from the LLM response (```repl or ```scheme code block)."
  (let ((str (if (string? response) response (scm->json response))))
    (cond
     ;; Prefer ```repl blocks (RLM style)
     ((string-contains str "```repl")
      (let* ((start (+ (string-contains str "```repl") 7))
             (end (string-contains str "```" start)))
        (if end (substring str start end) #f)))
     ;; Fallback: ```scheme blocks
     ((string-contains str "```scheme")
      (let* ((start (+ (string-contains str "```scheme") 9))
             (end (string-contains str "```" start)))
        (if end (substring str start end) #f)))
     (else #f))))

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
     (string-append "Syntax Error in your Scheme code: " message "\nPlease check parentheses and syntax. Remember: use (use-modules ...) NOT require."))
    ((permission)
     (string-append "Security Violation: " message "\nYou must use only allowed primitives. Use the pre-loaded tools from (gaia tools) instead."))
    ((runtime)
     (string-append "Runtime Error: " message "\nReview the logic and try debugging with display statements."))
    (else
     (string-append "Unknown Error: " message))))

(define MAX-RECURSION-DEPTH 15)
(define CONFIDENCE-THRESHOLD 95)

(define (rlm-loop session-id last-output depth . opt-env)
  "The core RLM loop. Maintains a persistent environment across iterations.
If opt-env is provided, uses that environment; otherwise creates a new one."
  (let ((env (if (null? opt-env)
                 (let ((new-env (make-rlm-env)))
                   ;; Inject llm-query: a closure that calls RAI
                   (rlm-inject! new-env 'llm-query
                     (lambda (prompt)
                       (let* ((sub-session (string-append session-id "-sub-" (number->string (random 1000000000))))
                              (response (chat-with-rai sub-session prompt (get-config 'model) SYSTEM_PROMPT))
                              (payload (assoc-ref response "payload")))
                         (if payload
                             (assoc-ref payload "content")
                             "Error: No response from sub-LLM"))))
                   ;; Inject context variable
                   (rlm-inject! new-env 'context last-output)
                   new-env)
                 (car opt-env))))

    (rlm-loop-inner session-id last-output depth env 1)))

;; --- Transcript helpers for multi-turn RLM loop ---

(define (truncate-for-transcript text)
  "Truncate text to keep transcript compact. Keep first 300 chars + last 100 chars."
  (let ((len (string-length text)))
    (if (<= len 500)
        text
        (string-append (substring text 0 300)
                       "\n... [truncated] ...\n"
                       (substring text (- len 100) len)))))

(define (format-transcript transcript)
  "Format transcript entries as a compact execution log.
   Entries are (role . text) pairs. Skip 'original-task' marker entries."
  (let ((step-num 0))
    (string-join
     (filter-map
      (lambda (entry)
        (let ((role (car entry))
              (text (cdr entry)))
          (cond
           ((string=? role "original-task") #f) ;; Skip marker
           ((string=? role "user")
            (set! step-num (+ step-num 1))
            (string-append "[Step " (number->string step-num) " input] " text))
           ((string=? role "assistant")
            (string-append "[Step " (number->string step-num) " response] " (truncate-for-transcript text)))
           (else #f))))
      transcript)
     "\n")))

(define (rlm-loop-inner session-id last-output depth env . opt-args)
  ;; opt-args: step [transcript]
  (let* ((step (if (null? opt-args) 1 (car opt-args)))
         (transcript (if (or (null? opt-args) (null? (cdr opt-args)))
                         '()
                         (cadr opt-args)))
         (prompt (if (null? transcript)
                     last-output
                     (let ((original-task (assoc-ref transcript "original-task"))
                           (history-text (format-transcript transcript)))
                       (string-append
                        "=== ORIGINAL TASK ===\n"
                        (if original-task original-task "Unknown task")
                        "\n\n=== EXECUTION LOG (steps so far) ===\n"
                        history-text
                        "\n\n=== LATEST ===\n"
                        last-output
                        "\n\nContinue working on the original task. "
                        "Write your next ```repl code block or provide FINAL(answer).")))))
    (if (> depth MAX-RECURSION-DEPTH)
        (begin
          (display "\n[GAIA] Max recursion depth reached. Returning current state.\n")
          last-output)
        (begin
          (display (string-append C-GREY "\n[GAIA] Step " (number->string step) " (Depth " (number->string depth) ")..." C-RESET "\n"))
          (let* ((response (chat-with-rai session-id prompt (get-config 'model) SYSTEM_PROMPT))
                 (payload (assoc-ref response "payload"))
                 (response-text (if payload (assoc-ref payload "content") "Error: No payload in response")))

            (display (string-append C-BLUE "\n[GAIA] Says: " C-RESET))
            (display response-text)
            (newline)

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

              (let ((updated-transcript
                     (append transcript
                             (if (= step 1)
                                 (list (cons "original-task" last-output)
                                       (cons "assistant" (truncate-for-transcript response-text))
                                       (cons "user" last-output))
                                 (list (cons "user" last-output)
                                       (cons "assistant" (truncate-for-transcript response-text)))))))

                (let ((has-action (or (extract-delegation response-text) (extract-code response-text)))
                      (has-final-signal (and final-sig #t)))
                  (if (and has-action has-final-signal)
                      (begin
                        (display (string-append C-RED "\n[GAIA] ⚠ Mixed action and FINAL signal in one turn." C-RESET "\n"))
                        (let ((feedback "Error: You provided both a ```repl code block and a FINAL() signal in the same response. Please provide ONLY the code block. After seeing the execution result, provide FINAL() in the NEXT response."))
                          (rlm-loop-inner session-id feedback depth env (+ step 1) updated-transcript)))
                      (cond
                       ((extract-delegation response-text) =>
                        (lambda (delegation)
                          (match delegation
                            (('delegate goal context-str)
                             (display (string-append C-YELLOW "\n[GAIA] Delegating sub-task..." C-RESET "\n"))
                             (let* ((sub-session-id (string-append session-id "-sub-" (number->string (random 1000000000))))
                                    (initial-input (string-append "GOAL: " goal "\nCONTEXT: " context-str))
                                    (sub-result (rlm-loop sub-session-id initial-input (+ depth 1))))
                               (display (string-append "\n[GAIA] Sub-task finished. Result: " sub-result "\n"))
                               (rlm-loop-inner session-id (string-append "Sub-agent execution finished. Result: " sub-result) depth env (+ step 1) updated-transcript)))
                            (_
                             (rlm-loop-inner session-id "Error: Invalid delegation format. Use (delegate \"Goal\" \"Context\")" depth env (+ step 1) updated-transcript)))))

                       ((extract-code response-text) =>
                        (lambda (code)
                          (if (and code (> (string-length code) 0) (not (string=? code response-text)))
                              (begin
                                (display (string-append C-YELLOW "\n[GAIA] Executing Code in RLM Environment..." C-RESET "\n"))
                                (match (rlm-execute env code)
                                  (('ok result)
                                   (display "\n[GAIA] Result: ")
                                   (display result)
                                   (newline)
                                   (let ((exec-log `(("session_id" . ,session-id)
                                                     ("code" . ,code)
                                                     ("result" . ,result)
                                                     ("type" . "execution")
                                                     ("status" . "success"))))
                                     (let ((port (open-file "trajectories.jsonl" "a")))
                                       (display (scm->json exec-log) port)
                                       (newline port)
                                       (close-port port)))
                                   (rlm-loop-inner session-id (string-append "Code executed successfully. Result:\n" result) depth env (+ step 1) updated-transcript))

                                  (('error type msg)
                                   (let ((feedback (handle-error type msg depth)))
                                     (display (string-append C-RED "\n[GAIA] Error: " feedback C-RESET "\n"))
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
                                     (rlm-loop-inner session-id feedback depth env (+ step 1) updated-transcript)))))
                              response-text)))

                       ((and final-sig (match final-sig (('final ans) ans) (('final-var var) var) (_ #f))) =>
                        (lambda (answer)
                          (display (string-append C-GREEN "\n[GAIA] ✓ FINAL signal detected." C-RESET "\n"))
                          (if (equal? (car final-sig) 'final)
                              (display (string-append C-BOLD "[GAIA] Answer: " C-RESET answer "\n"))
                              (display (string-append C-BOLD "[GAIA] Answer stored in: " C-RESET answer "\n")))
                          answer))

                       ((and conf-val (>= conf-val CONFIDENCE-THRESHOLD))
                        (display (string-append C-GREEN "\n[GAIA] ✓ High confidence (" (number->string conf-val) "%) - stopping." C-RESET "\n"))
                        response-text)

                       (else
                        (display (string-append C-RED "\n[GAIA] ⚠ No actionable output. Treating as final answer (unless low confidence)." C-RESET "\n"))
                        response-text)))))))))))


(define (handle-command input session-id)
  "Parses and executes meta-commands or delegates to RLM."
  (cond
   ;; /exit
   ((string=? input "/exit")
    (display "Bye.\n")
    #f) ;; Return #f to stop loop

   ;; /help
   ((string=? input "/help")
    (display (string-append C-BOLD "Available commands:" C-RESET "\n"))
    (display "  /ask <query>   - One-shot question to AI (no RLM loop)\n")
    (display "  /eval <scheme> - Execute Scheme code locally\n")
    (display "  /models        - List available models and LoRA adapters\n")
    (display "  /model <name>  - Select a base model or LoRA adapter folder to load\n")
    (display "  /backend <name>- Select the backend to use (e.g. local, ollama)\n")
    (display "  /base-model <name>- Select the foundation model used for training\n")
    (display "  /train         - Manually trigger Fine Tuning (make learn) from dataset\n")
    (display "  /help          - Show this help\n")
    (display "  /exit          - Quit GAIA\n")
    (display "  <query>        - Start standard RLM investigation\n")
    #t)

   ;; /ask <query>
   ((string-prefix? "/ask " input)
    (let ((query (substring input 5)))
      (display "[Direct Question] Asking AI...\n")
      (let* ((response (chat-with-rai session-id query (get-config 'model) "You are a helpful Guile Scheme expert."))
             (payload (assoc-ref response "payload"))
             (content (if payload (assoc-ref payload "content") "Error No Payload")))
        (display "\nAI: ")
        (display content)
        (newline))
      #t))

   ;; /eval <scheme>
   ((string-prefix? "/eval " input)
    (let ((code (substring input 6)))
      (catch #t
        (lambda ()
          (display (eval-string code))
          (newline))
        (lambda (key . args)
          (display (format #f "Error: ~a ~a\n" key args)))))
    #t)

   ;; /models
   ((string=? input "/models")
    (let ((models-alist (get-models)))
       (display (string-append C-BOLD "Available models (from RAI Registry):\n" C-RESET))
       (if (list? models-alist)
           (for-each (lambda (pair)
                       (let ((backend (car pair))
                             (model-vec (cdr pair)))
                         (display (string-append C-CYAN "  [" backend "]:\n" C-RESET))
                         (if (vector? model-vec)
                             (vector-for-each (lambda (i m) (display (string-append "    - " m "\n"))) model-vec)
                             (for-each (lambda (m) (display (string-append "    - " m "\n"))) model-vec))))
                     models-alist)
           (display (string-append C-RED "  No models found or unexpected response format.\n" C-RESET))))
    #t)

   ;; /model
   ((string=? input "/model")
    (display (string-append C-BOLD "Current model: " C-RESET (get-config 'model) "\n"))
    #t)

   ;; /model <name>
   ((string-prefix? "/model " input)
    (let ((new-model (substring input 7)))
       (set-config! 'model new-model)
       (display (string-append C-GREEN "Model hot-swapped for session to: " C-RESET new-model "\n")))
    #t)

   ;; /backend
   ((string=? input "/backend")
    (display (string-append C-BOLD "Current backend: " C-RESET (get-config 'backend) "\n"))
    #t)

   ;; /backend <name>
   ((string-prefix? "/backend " input)
    (let ((new-backend (substring input 9)))
       (set-config! 'backend new-backend)
       (display (string-append C-GREEN "Backend hot-swapped for session to: " C-RESET new-backend "\n")))
    #t)

   ;; /base-model
   ((string=? input "/base-model")
    (display (string-append C-BOLD "Current base model for training: " C-RESET (get-config 'base-model) "\n"))
    #t)

   ;; /base-model <name>
   ((string-prefix? "/base-model " input)
    (let ((new-base (substring input 12)))
       (set-config! 'base-model new-base)
       (display (string-append C-GREEN "Base model for training hot-swapped to: " C-RESET new-base "\n")))
    #t)

   ;; /train
   ((string=? input "/train")
    (display (string-append C-YELLOW "Triggering model training...\n" C-RESET))
    (let ((current-base (get-config 'base-model)))
      (setenv "GAIA_BASE_MODEL" current-base)
      (system* "make" "learn")
      (setenv "GAIA_BASE_MODEL" ""))
    #t)

   ;; Standard RLM Loop
   (else
    (rlm-loop session-id input 0)
    #t)))

(define (start-gaia . args)
  (activate-readline)
  (display (string-append C-BOLD C-GREEN "Initializing GAIA (GNU AI Assistant)..." C-RESET "\n"))

  (load-config)
  (display (format #f "Config Loaded:\n  Model: ~a~a~a\n  Backend: ~a\n  URL: ~a\n"
                   C-CYAN (get-config 'model) C-RESET
                   (get-config 'backend)
                   (get-config 'rai-url)))

  (display "Type '/help' for commands or enter a task.\n")

  (let ((session-id (string-append "gaia-"
                                   (number->string (current-time))
                                   "-"
                                   (number->string (random 10000)))))

    (display (string-append "Session ID: " session-id "\n"))

    (let loop ()
      (newline)
      (let ((input (readline (string-append "\x01" C-BOLD C-GREEN "\x02(GAIA) >\x01" C-RESET "\x02 "))))
        (cond
         ((eof-object? input) (newline))
         ((string=? input "") (loop))
         (else
          (add-history input) ;; Add to readline history
          (if (handle-command input session-id)
              (loop)
              #t)))))))
