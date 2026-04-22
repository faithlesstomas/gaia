(define-module (gaia core)
  #:use-module (gaia llm-client)
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
- Language: GNU Guile Scheme.
- CRITICAL: Use `(use-modules ...)` for imports.
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
- `(search-file pattern path-to-file)` — Grep for PATTERN in FILE. Example: `(search-file \"SECRET\" \"haystack.txt\")`.
  Returns matching lines as a string.
- `(search-guile-manual pattern)` — Search the official Guile documentation using info. Example: `(search-guile-manual \"format\")`
- `(run-sed expression path)` — Runs sed expression on file (stdout only).
- `(run-awk program path)` — Runs awk program on file.
- `(list-boots)` — Lists history of system boots. Use to find boot-ids.
- `(get-boot-logs [boot-id] [lines])` — Get logs for specific boot (default: current boot, 100 lines).
- `(get-system-logs service [lines] [since] [until])` — Logs for service (e.g. \"sshd\"). Time format: \"YYYY-MM-DD HH:MM:SS\".
- `(get-recent-logs [lines] [priority])` — General logs. Priority: \"emerg\", \"err\", \"warning\", \"info\".
- `(get-kernel-logs [lines] [since])` — Kernel logs (dmesg style).
- LIMIT: All log tools are capped at 500 lines per call.

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

# GUILE-SPECIFIC WARNINGS & LIMITATIONS (READ CAREFULLY)
- CRITICAL SCOPE RULE: NEVER place `(define ...)` inside expression contexts like `if`, `cond`, `while` or `dolist`.
  To create local scope, use `(let (...))` or `(let* (...))`. To reassign existing bindings, use `(set! var val)`.
- FORMAT FUNCTION: In Guile, `(format ...)` MUST specify a destination port. To return a string, use `#f`.
  To print to stdout, use `#t`. Example: `(format #f \"Hello ~a\" name)`.
- CHARACTERS: Guile character literals start with `#\\`. Use `#\\space`, `#\\newline`, `#\\.`, `#\\/`.
  Do not invent macros like `#/.`. Note that Guile's built-in `string-split` takes a CHARACTER!
  Example: `(string-split \"hello world\" #\\space)`.
- SYNTAX ERRORS: If you get `Syntax Error: unexpected end of input while searching for: ~A ()`, you MISSED a closing parenthesis `)`.
  DO NOT rewrite the code from scratch – carefully match your parenthesis.
- FLAT CODE: Write simple, flat code blocks instead of deeply nested lists to minimize parenthesis mismatches.
  Let-loops and state accumulators work well.
- CHEATSHEET: If you are repeatedly failing checks, read the common gotchas via `(read-file \"docs/guile-gotchas.md\")`.

# HOW TO WRITE CODE
Wrap your Guile Scheme code in a ```repl code block:
```repl
(let loop ((files (list-files \"/workspace\"))
           (count 0))
  (if (null? files)
      (display count)
      (loop (cdr files) (+ count 1))))
```

The system will execute your code and return the output. You can then reason about the output and write more code.

# COMPLETION SIGNALS
When you have solved the task COMPLETELY, use ONE of these signals:
- `FINAL(answer)` — For direct text answers. Example: `FINAL(The file contains 42 errors)`
- `FINAL_VAR(variable_name)` — For answers stored in a variable from code execution.

After each step, rate your confidence:
- `CONFIDENCE(score)` — 0-100%. If >= 95%, the system stops automatically.

# RESEARCH & DEBUGGING PROTOCOL
1. **Search Before You Leap**: If you are unsure about a function signature, return type, or which module to use,
   your FIRST step must be to use `(search-guile-manual \"pattern\")`.
2. **Handle Errors with Research**: If you encounter an `unbound-variable` error, DO NOT guess the name.
   Search the manual for the variable or feature you need to find the correct naming or the required module.
3. **Use Standard Modules**: Standard Guile modules like `(ice-9 ftw)` (for file tree walks) and `(ice-9 textual-ports)` are already available.
   Use `search-guile-manual` to learn how to use them instead of reinventing complex logic.
4. **POSIX Tools**: You have direct access to `stat`, `lstat`, `access`, and `file-exists?`. Use them for low-level file system logic.

# MACRO-RECURSION & DELEGATION (CRITICAL FOR COMPLEX TASKS)
If a task requires processing large files (logs), broad searches, or complex decoupled reasoning, you MUST DELEGATE it to a sub-agent.
- Use a code block with language 'delegate' containing an S-expression: `(delegate \"Goal\" \"Context\")`.
- WARNING: `delegate` IS NOT A SCHEME FUNCTION! DO NOT write it inside your ```repl blocks! It is a distinct markdown block used directly in your text response.
- CRITICAL: The `delegate` block is parsed textually. It CANNOT access your Scheme variables!
  If you have downloaded data into variables (like `logs`) and want an LLM to synthesize them, DO NOT use `delegate`.
  Instead, construct a prompt string inside your code and use `(llm-query your-prompt)`.
  Example for in-memory data synthesis: `(display (llm-query (string-append \"Analyze: \" logs)))`
- The system will spawn a FRESH, isolated agent and wait for its completion.
- The sub-agent will return its processed summarization back to your loop.

Example of standard delegation (no Scheme variables):
```delegate
(delegate \"Find 'Permission Denied' errors in sshd logs\" \"Using get-recent-logs or get-system-logs sshd\")
```

# CRITICAL RULES
1. NEVER put FINAL() or FINAL_VAR() in the same response as a ```repl code block!
   Write code → WAIT for results → then provide FINAL() in NEXT response.
   Note: CONFIDENCE() alongside code is OK and expected.
2. Use the pre-loaded tools and modules. Do NOT try to import them again.
3. Think step by step. Use `display` or `write` to inspect intermediate results.
4. For large data: use `search-file` to find relevant lines. NEVER try to display entire large files.
5. KEEP IT SHORT: Write short REPL commands. The environment may enforce a strict max line limit (e.g., 15 lines).
   Store intermediate results in global variables using `(define var ...)` and process them in the next step.
   Do not write massive monolithic scripts!
6. SINGLE BLOCK: Only the LAST ```repl code block in your response will be executed.
   If you self-correct your thinking, make sure your final, intended code is in the last ```repl block.
7. NO TRIVIAL DELEGATION: NEVER use `delegate` for summarizing, formatting, or translating text.
   You are fully capable of writing in the user's language. ONLY delegate for deep, isolated technical investigations.

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

(define (string-contains-last str pattern)
  (let loop ((start 0)
             (last-idx #f))
    (let ((idx (string-contains str pattern start)))
      (if idx
          (loop (+ idx (string-length pattern)) idx)
          last-idx))))

(define (extract-code response)
  "Extracts Scheme code from the LLM response (```repl or ```scheme code block).
Prefers the LAST code block to support LLM self-correction patterns."
  (let ((str (if (string? response) response (scm->json response))))
    (cond
     ;; Prefer ```repl blocks (RLM style)
     ((string-contains-last str "```repl")
      => (lambda (idx)
           (let* ((start (+ idx 7))
                  (end (string-contains str "```" start)))
             (if end (substring str start end) #f))))
     ;; Fallback: ```scheme blocks
     ((string-contains-last str "```scheme")
      => (lambda (idx)
           (let* ((start (+ idx 9))
                  (end (string-contains str "```" start)))
             (if end (substring str start end) #f))))
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
    (let ((final-idx (string-contains str "FINAL(")))
      (if final-idx
          (let* ((start (+ final-idx 6))
                 (conf-idx (string-contains str "CONFIDENCE(" start))
                 (search-space (substring str start (if conf-idx conf-idx (string-length str))))
                 (end-local (string-rindex search-space #\))))
            (if end-local
                (list 'final (string-trim-both (substring search-space 0 end-local)))
                #f))
          (let ((fvar-idx (string-contains str "FINAL_VAR(")))
            (if fvar-idx
                (let* ((start (+ fvar-idx 10))
                       (conf-idx (string-contains str "CONFIDENCE(" start))
                       (search-space (substring str start (if conf-idx conf-idx (string-length str))))
                       (end-local (string-rindex search-space #\))))
                  (if end-local
                      (list 'final-var (string-trim-both (substring search-space 0 end-local)))
                      #f))
                #f))))))

(define (extract-confidence response)
  "Extracts CONFIDENCE(score) or <confidence>score</confidence> from LLM response. Returns number 0-100 or #f."
  (let ((str (if (string? response) response (scm->json response))))
    (cond
     ((string-match "CONFIDENCE\\(([0-9]+)\\)" str) =>
      (lambda (m)
        (let ((score (string->number (match:substring m 1))))
          (if (and score (>= score 0) (<= score 100))
              score
              #f))))
     ((string-match "<confidence>([0-9]+)</confidence>" str) =>
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
(define thinking-enabled? #f) ;; Default thinking off

(define (rlm-loop session-id last-output depth history . opt-env)
  "The core RLM loop. Maintains a persistent environment across iterations.
If opt-env is provided, uses that environment; otherwise creates a new one."
  (let ((env (if (null? opt-env)
                 (let ((new-env (make-rlm-env)))
                   ;; Inject llm-query: a closure that calls LLM proxy
                   (rlm-inject! new-env 'llm-query
                     (lambda (prompt)
                       (let* ((sub-session (string-append session-id "-sub-" (number->string (random 1000000000))))
                              (response (chat-with-llm sub-session prompt (get-config 'model) (or (get-config 'system-prompt) SYSTEM_PROMPT) #:history history))
                              (payload (assoc-ref response "payload")))
                         (if payload
                             (assoc-ref payload "content")
                             "Error: No response from sub-LLM"))))
                   ;; Inject context variable
                   (rlm-inject! new-env 'context last-output)
                   new-env)
                 (car opt-env))))

    (rlm-loop-inner session-id last-output depth env history 1)))

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

(define (strip-blocks text)
  "Strips markdown code blocks, thought blocks, and internal tokens from text."
  (let loop ((t text))
    (let ((start (string-contains t "<thought>"))
          (end (string-contains t "</thought>")))
      (if (and start end (> end start))
          (loop (string-append (substring t 0 start) (substring t (+ end 10))))
          (let loop2 ((t t))
            (let ((c-start (string-contains t "```")))
              (if c-start
                  (let ((c-end (string-contains t "```" (+ c-start 3))))
                    (if c-end
                        (loop2 (string-append (substring t 0 c-start) (substring t (+ c-end 3))))
                        t))
                  (let* ((t (regexp-substitute/global #f "<channel\\|>" t 'pre "" 'post))
                         (t (regexp-substitute/global #f "<unused87>tool_code" t 'pre "" 'post))
                         (t (regexp-substitute/global #f "<unused88>" t 'pre "" 'post))
                         (t (regexp-substitute/global #f "<\\|think\\|>" t 'pre "" 'post)))
                    (string-trim-both t)))))))))

(define (markdown->ansi text)
  "Converts simple markdown to ANSI sequences."
  (let* ((t (regexp-substitute/global #f "\\*\\*([^*]+)\\*\\*" text 'pre C-BOLD 1 C-RESET 'post))
         (t (regexp-substitute/global #f "`([^`]+)`" t 'pre C-CYAN 1 C-RESET 'post)))
    t))

(define (rlm-loop-inner session-id last-output depth env history . opt-args)
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
          (display (string-append C-GREY "\n[GAIA] Agent Depth " (number->string depth) " (Step " (number->string step) ")..." C-RESET "\n"))
          (let* ((response (chat-with-llm session-id prompt (get-config 'model) (or (get-config 'system-prompt) SYSTEM_PROMPT) #:think thinking-enabled? #:history history))
                 (payload (assoc-ref response "payload"))
                 (response-text (if payload
                                    (assoc-ref payload "content")
                                    (let ((err (assoc-ref response "error")))
                                      (if err
                                          (string-append "Error from LLM API: " (if (string? err) err (format #f "~a" err)))
                                          "Error: No payload in response"))))
                 (reasoning-text (if payload (assoc-ref payload "reasoning") "")))

            (let ((final-sig (extract-final-signal response-text))
                  (conf-val (extract-confidence response-text)))

              ;; Log interaction FIRST so reasoning trace is captured
              (let ((log-entry `(("session_id" . ,session-id)
                                 ("prompt" . ,prompt)
                                 ("input" . ,last-output)
                                 ("response" . ,response-text)
                                 ("reasoning" . ,reasoning-text)
                                 ("timestamp" . ,(number->string (current-time)))
                                 ("confidence" . ,(if conf-val conf-val "null"))
                                 ("final_signal" . ,(if final-sig "true" "false")))))
                (let ((port (open-file (or (getenv "GAIA_TRAJECTORIES_FILE") "trajectories.jsonl") "a")))
                  (display (scm->json log-entry) port)
                  (newline port)
                  (close-port port)))

              ;; Guard against empty responses from the model
              (if (string=? response-text "")
                  (begin
                    (display (string-append C-RED "\n[GAIA] Empty response from model. Retrying..." C-RESET "\n"))
                    (let ((retry-transcript
                           (if (= step 1)
                               (list (cons "original-task" last-output)
                                     (cons "user" last-output)
                                     (cons "assistant" "(empty response)"))
                               (append transcript
                                       (list (cons "user" last-output)
                                             (cons "assistant" "(empty response)"))))))
                      (rlm-loop-inner session-id
                        "Your previous response was empty. Please write a ```repl code block to continue working on the task, or provide FINAL(answer) if you have the answer."
                        depth env history (+ step 1) retry-transcript)))

                  (let ((updated-transcript
                     (append transcript
                             (if (= step 1)
                                 (list (cons "original-task" last-output)
                                       (cons "assistant" (truncate-for-transcript response-text))
                                       (cons "user" last-output))
                                 (list (cons "user" last-output)
                                       (cons "assistant" (truncate-for-transcript response-text)))))))

                (when (and reasoning-text (> (string-length reasoning-text) 0))
                  (display (string-append C-GREY "[GAIA] Thinking asynchronously... (See monitor)" C-RESET "\n")))

                (let ((prose (strip-blocks response-text)))
                  (when (> (string-length prose) 0)
                    (display (string-append C-BLUE "\n[GAIA] Analysis: " C-RESET (markdown->ansi prose) "\n"))))

                (let ((has-action (or (extract-delegation response-text) (extract-code response-text)))
                      (has-final-signal (and final-sig #t)))
                  (if (and has-action has-final-signal)
                      (begin
                        (display (string-append C-RED "\n[GAIA] ⚠ Mixed action and FINAL signal in one turn." C-RESET "\n"))
                        (let ((feedback "Error: You provided both a ```repl code block and a FINAL() signal in the same response. Please provide ONLY the code block. After seeing the execution result, provide FINAL() in the NEXT response."))
                          (rlm-loop-inner session-id feedback depth env history (+ step 1) updated-transcript)))
                      (cond
                       ((extract-delegation response-text) =>
                        (lambda (delegation)
                          (match delegation
                            (('delegate goal context-str)
                             (display (string-append C-BOLD C-YELLOW "\n[GAIA] Spawning Sub-Agent (Delegation):\n" C-RESET "Goal: " goal "\nContext: " context-str "\n"))
                             (let* ((sub-session-id (string-append session-id "-sub-" (number->string (random 1000000000))))
                                    (initial-input (string-append "GOAL: " goal "\nCONTEXT: " context-str))
                                    (sub-result (rlm-loop sub-session-id initial-input (+ depth 1) history)))
                               (display (string-append C-BOLD C-GREEN "\n[GAIA] Sub-Agent completed.\n" C-RESET "Result length: " (number->string (string-length sub-result)) " chars\n"))
                               (rlm-loop-inner session-id (string-append "Sub-agent execution finished. Result: " sub-result) depth env history (+ step 1) updated-transcript)))
                            (_
                             (rlm-loop-inner session-id "Error: Invalid delegation format. Use (delegate \"Goal\" \"Context\")" depth env history (+ step 1) updated-transcript)))))

                       ((extract-code response-text) =>
                        (lambda (code)
                          (if (and code (> (string-length code) 0) (not (string=? code response-text)))
                              (begin
                                (display (string-append C-BOLD C-CYAN "\n[GAIA] Executing Scheme Code:\n" C-RESET code "\n"))
                                (match (rlm-execute env code)
                                  (('ok result)
                                   (display (string-append C-GREEN "\n[REPL] Success:\n" C-RESET result "\n"))
                                   (let ((exec-log `(("session_id" . ,session-id)
                                                     ("code" . ,code)
                                                     ("result" . ,result)
                                                     ("type" . "execution")
                                                     ("status" . "success"))))
                                     (let ((port (open-file (or (getenv "GAIA_TRAJECTORIES_FILE") "trajectories.jsonl") "a")))
                                       (display (scm->json exec-log) port)
                                       (newline port)
                                       (close-port port)))
                                   (rlm-loop-inner session-id (string-append "Code executed successfully. Result:\n" result) depth env history (+ step 1) updated-transcript))

                                  (('error type msg)
                                   (let ((feedback (handle-error type msg depth)))
                                     (display (string-append C-RED "\n[REPL] Runtime Error:\n" C-RESET feedback "\n"))
                                     (let ((exec-log `(("session_id" . ,session-id)
                                                       ("code" . ,code)
                                                       ("result" . ,feedback)
                                                       ("type" . "execution")
                                                       ("status" . "error")
                                                       ("error_type" . ,(symbol->string type)))))
                                       (let ((port (open-file (or (getenv "GAIA_TRAJECTORIES_FILE") "trajectories.jsonl") "a")))
                                         (display (scm->json exec-log) port)
                                         (newline port)
                                         (close-port port)))
                                     (rlm-loop-inner session-id feedback depth env history (+ step 1) updated-transcript)))))
                              response-text)))

                       ((and final-sig (match final-sig (('final ans) ans) (('final-var var) var) (_ #f))) =>
                        (lambda (answer)
                          (display (string-append C-GREEN "\n[GAIA] ✓ FINAL signal detected." C-RESET "\n"))
                          (if (equal? (car final-sig) 'final)
                              (display (string-append C-BOLD "[GAIA] Final Answer: " C-RESET (markdown->ansi answer) "\n"))
                              (display (string-append C-BOLD "[GAIA] Answer stored in: " C-RESET answer "\n")))
                          answer))

                       ((and conf-val (>= conf-val CONFIDENCE-THRESHOLD))
                        (display (string-append C-GREEN "\n[GAIA] ✓ High confidence (" (number->string conf-val) "%) - stopping." C-RESET "\n"))
                        response-text)

                       (else
                        (display (string-append C-RED "\n[GAIA] ⚠ No actionable output. Treating as final answer (unless low confidence)." C-RESET "\n"))
                        response-text))))))))))))

(define (handle-command input session-id history)
  "Parses and executes meta-commands or delegates to RLM.
Returns updated (history . should-continue?)"
  (cond
   ;; /exit
   ((string=? input "/exit")
    (display "Bye.\n")
    (cons history #f))

   ;; /help
   ((string=? input "/help")
    (display (string-append C-BOLD "Available commands:" C-RESET "\n"))
    (display "  /ask <query>   - One-shot question to AI (no RLM loop)\n")
    (display "  /eval <scheme> - Execute Scheme code locally\n")
    (display "  /models        - List available models and LoRA adapters\n")
    (display "  /model <name>  - Select a base model or LoRA adapter folder to load\n")
    (display "  /thinking [on|off]- Enable, disable, or check thinking mode (reasoning)\n")
    (display "  /base-model <name>- Select the foundation model used for training\n")
    (display "  /train         - Manually trigger Fine Tuning (make learn) from dataset\n")
    (display "  /clear         - Clear conversation history\n")
    (display "  /help          - Show this help\n")
    (display "  /exit          - Quit GAIA\n")
    (display "  <query>        - Start standard RLM investigation\n")
    (cons history #t))

   ;; /clear
   ((string=? input "/clear")
    (display (string-append C-YELLOW "Conversation history cleared." C-RESET "\n"))
    (cons '() #t))

   ;; /ask <query>
   ((string-prefix? "/ask " input)
    (let ((query (substring input 5)))
      (display "[Direct Question] Asking AI...\n")
      (let* ((response (chat-with-llm session-id query (get-config 'model) "You are a helpful Guile Scheme expert." #:history history))
             (payload (assoc-ref response "payload"))
             (content (if payload (assoc-ref payload "content") "Error No Payload")))
        (display "\nAI: ")
        (display content)
        (newline)
        (cons (append history (list `(("role" . "user") ("content" . ,query))
                                    `(("role" . "assistant") ("content" . ,content))))
              #t))))

   ;; /eval <scheme>
   ((string-prefix? "/eval " input)
    (let ((code (substring input 6)))
      (catch #t
        (lambda ()
          (display (eval-string code))
          (newline))
        (lambda (key . args)
          (display (format #f "Error: ~a ~a\n" key args))))
      (cons history #t)))

   ;; /models
   ((string=? input "/models")
    (let ((models-list (get-models)))
       (display (string-append C-BOLD "Available models (from LLM Registry):\n" C-RESET))
       (if (list? models-list)
           (for-each (lambda (m) (display (string-append "  - " m "\n"))) models-list)
           (display (string-append C-RED "  No models found or unexpected response format.\n" C-RESET))))
    (cons history #t))

   ;; /model
   ((string=? input "/model")
    (display (string-append C-BOLD "Current model: " C-RESET (get-config 'model) "\n"))
    (cons history #t))

   ;; /model <name>
   ((string-prefix? "/model " input)
    (let ((new-model (substring input 7)))
       (set-config! 'model new-model)
       (display (string-append C-GREEN "Model hot-swapped for session to: " C-RESET new-model "\n")))
    (cons history #t))

   ;; /thinking
   ((string=? input "/thinking")
    (display (string-append "Current thinking mode: " (if thinking-enabled? "ON" "OFF") "\n"))
    (cons history #t))

   ;; /thinking <on/off>
   ((string-prefix? "/thinking " input)
    (let ((arg (string-trim-both (substring input 10))))
      (cond
       ((or (string=? arg "on") (string=? arg "1"))
        (set! thinking-enabled? #t)
        (display (string-append C-CYAN "Thinking mode ENABLED." C-RESET "\n")))
       ((or (string=? arg "off") (string=? arg "0"))
        (set! thinking-enabled? #f)
        (display (string-append C-YELLOW "Thinking mode DISABLED." C-RESET "\n")))
       (else
        (display (string-append "Current thinking mode: " (if thinking-enabled? "ON" "OFF") "\n"))))
      (cons history #t)))

   ;; /base-model
   ((string=? input "/base-model")
    (display (string-append C-BOLD "Current base model for training: " C-RESET (get-config 'base-model) "\n"))
    (cons history #t))

   ;; /base-model <name>
   ((string-prefix? "/base-model " input)
    (let ((new-base (substring input 12)))
       (set-config! 'base-model new-base)
       (display (string-append C-GREEN "Base model for training hot-swapped to: " C-RESET new-base "\n")))
    (cons history #t))

   ;; /train
   ((string=? input "/train")
    (display (string-append C-YELLOW "Triggering model training...\n" C-RESET))
    (let ((current-base (get-config 'base-model)))
      (setenv "GAIA_BASE_MODEL" current-base)
      (system* "make" "learn")
      (setenv "GAIA_BASE_MODEL" ""))
    (cons history #t))

   ;; Standard RLM Loop
   (else
    (let ((answer (rlm-loop session-id input 0 history)))
      (cons (append history (list `(("role" . "user") ("content" . ,input))
                                  `(("role" . "assistant") ("content" . ,answer))))
            #t)))))

(define (start-gaia . args)
  (activate-readline)
  (display (string-append C-BOLD C-GREEN "Initializing GAIA (GNU AI Assistant)..." C-RESET "\n"))

  (load-config)
  (display (format #f "Config Loaded:\n  Model: ~a~a~a\n  URL: ~a\n"
                   C-CYAN (get-config 'model) C-RESET
                   (get-config 'llm-url)))

  (display "Type '/help' for commands or enter a task.\n")

  (let ((session-id (string-append "gaia-"
                                   (number->string (current-time))
                                   "-"
                                   (number->string (random 10000)))))

    (display (string-append "Session ID: " session-id "\n"))

    (let loop ((chat-history '()))
      (newline)
      (let ((input (readline (string-append "\x01" C-BOLD C-GREEN "\x02(GAIA) >\x01" C-RESET "\x02 "))))
        (cond
         ((eof-object? input) (newline))
         ((string=? input "") (loop chat-history))
         (else
          (add-history input) ;; Add to readline history
          (let* ((result (handle-command input session-id chat-history))
                 (new-history (car result))
                 (continue? (cdr result)))
            (if continue?
                (loop new-history)
                #t))))))))
