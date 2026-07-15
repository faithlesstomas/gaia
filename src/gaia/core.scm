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
  #:export (start-gaia SYSTEM_PROMPT get-system-prompt get-solver-system-prompt extract-code extract-final-signal extract-confidence
            extract-delegation markdown->ansi MAX-RECURSION-DEPTH CONFIDENCE-THRESHOLD
            C-RESET C-BOLD C-RED C-GREEN C-YELLOW C-BLUE C-CYAN C-GREY
            start-gaia rlm-loop *interrupted* check-interrupt! gaia-log clean-assistant-content
            format-transcript truncate-for-transcript))




(define C-RESET "\x1b[0m")
(define C-BOLD "\x1b[1m")
(define C-RED "\x1b[31m")
(define C-GREEN "\x1b[32m")
(define C-YELLOW "\x1b[33m")
(define C-BLUE "\x1b[34m")
(define C-CYAN "\x1b[36m")
(define C-GREY "\x1b[90m")
(define (gaia-log . args)
  (let* ((text (string-join (map (lambda (a) (format #f "~a" a)) args) ""))
         (text (string-map (lambda (c) (if (char=? c #\return) #\space c)) text))
         (lines (string-split text #\newline))
         (timestamp (strftime "%Y-%m-%d %H:%M:%S" (localtime (current-time)))))
    (for-each (lambda (line)
                (let ((trimmed (string-trim-both line)))
                  (unless (string-null? trimmed)
                    (let ((formatted-line (format #f "[~a] ~a" timestamp trimmed)))
                      ;; 1. Display to stdout (ANSI colored)
                      (display (string-append formatted-line "\n"))
                      (force-output)
                      ;; 2. Write to gaia-server.log (ANSI stripped)
                      (catch #t
                        (lambda ()
                          (let* ((clean-line (regexp-substitute/global #f "\x1b\\[[0-9;]*m" formatted-line 'pre "" 'post))
                                 (port (open-file "gaia-server.log" "a")))
                            (display (string-append clean-line "\n") port)
                            (close-port port)))
                        (lambda _ #f))))))
              lines)))

;; Flag-based interrupt: signal handler sets flag, checked at safe points
(define *interrupted* #f)

(define (check-interrupt!)
  "Check if user pressed Ctrl-C and throw if so.
  Uses a flag because throw from async signal handlers is unreliable
  during blocking C code (e.g. http-post)."
  (when *interrupted*
    (set! *interrupted* #f)
    (throw 'user-interrupt)))

(define SYSTEM_PROMPT
  "# ROLE
You are GAIA (GNU AI Assistant), an autonomous system operator executing tasks inside a stateful, persistent GNU Guile Scheme REPL.
You solve complex objectives iteratively by writing and evaluating Scheme code. Your environment preserves all variables
and functions across steps (stateful programming) and provides native tools for nested reasoning (via `llm-query` calls)
and spawning auxiliary sub-agents (via `delegate` blocks) to divide and conquer tasks.

# EXECUTION ENVIRONMENT
- Language: GNU Guile Scheme.
- CRITICAL: Use `(use-modules ...)` for imports.
- Your code runs in a persistent REPL: variables and functions you define in one step are available in the next.
- Output from `display`, `write`, `format` is captured and returned to you.
- **Transactional REPL:** If your code throws a syntax or runtime error, the state mutations for that entire step are rolled back.
  Ensure your code is syntactically and logically correct to persist variables.
- **Wisp (SRFI-119) Support:** You can write Scheme code using Python-like indentation instead of nested parentheses. Wrap your block in ```wisp instead of ```repl. When using Wisp:
  - Use 2-space indentation to nest expressions.
  - A variable assignment like `define name \"val\"` should be on one line.
  - If a value/string literal is on an indented line, prefix it with `.` to prevent the parser from wrapping it in a list (e.g., `define name \n  . \"val\"` instead of `define name \n  \"val\"` which translates to calling `\"val\"` as a function).
  - Wisp is native to GNU Guile via `(language wisp spec)` and follows the SRFI-119 specification (Wisp: Lisp with indentation). Refer to SRFI-119 documentation for full syntax.

# PRE-LOADED MODULES (already available, no need to import)
- `(srfi srfi-1)` — List library: `filter`, `fold`, `any`, `every`, `partition`, etc.
- `(srfi srfi-13)` — String library: `string-contains`, `string-prefix?`, `string-suffix?`, `string-trim`, etc.
- `(ice-9 regex)` — Regex: `string-match`, `match:substring`, etc.
- `(ice-9 match)` — Pattern matching: `(match expr ((pattern) body) ...)`.
- `(ice-9 rdelim)` — I/O: `read-line`, `read-string`.
- `(ice-9 ftw)` — File traversal: `scandir`, `file-system-fold`.

# AVAILABLE TOOLS (from `(gaia tools)`, already loaded)
- `(list-files path)` — Returns list of files in directory.
- `(find-files base-dir pattern)` — Recursively searches for files/directories matching the regex PATTERN starting from BASE-DIR. Example: `(find-files \"/home/user/projects\" \"\\\\.scm$\")`.
- `(read-file path)` — Returns file content as string. WARNING: for large files, do NOT display the output! Use search-file instead.
- `(write-file path content)` — Writes string to file.
- `(delete-file path)` — Safely deletes a file (requires user permission).
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
- `(git-status)` — Returns brief workspace status.
- `(git-diff [path])` — Returns git diff (highly recommended before finalizing changes!).
- `(git-log [count])` — Shows recent git commits (oneline format).
- `(git-ls-files)` — Returns a LIST of strings (all tracked files). Use `(length (git-ls-files))` to count them.
- `(guix-search query)` — Searches for packages in GNU Guix.
- `(guix-package-info name)` — Gets detailed package metadata.
- `(run-in-sandbox cmd)` — Executes a shell command inside an isolated Guix container (has git, coreutils, grep, sed, awk).
  Starts in the `/workspace` directory. Use for complex shell pipelines like `(run-in-sandbox \"ls | wc -l\")`.
  WARNING: The container is fully isolated and does NOT mount the user's home directory or sibling directories outside the current workspace.
  It cannot access any files outside the `/workspace` directory (which maps to the active project workspace).
- `(run-python code)` — Stateful, persistent Python execution. Runs the given `code` string in a secure Python REPL container.
  Variables, functions, and imports in Python persist across `(run-python ...)` calls within the session.
- `(guile-syntax-check code-string)` — Validates Scheme syntax without evaluating it.
- `(fork-sandbox)` — Clones the current REPL environment.
- SHELL PIPES: Shell pipes `|` and redirections `>` only work inside the `cmd` string of `run-in-sandbox`.
  Example: `(run-in-sandbox \"ls | wc -l\")` is VALID. `(ls | wc -l)` is INVALID Scheme.

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
- SANDBOX WHITELIST: For security, the Scheme REPL runs in a restricted sandbox. Functions like `getenv` and mathematical primitives like `sqrt` are NOT whitelisted and will throw `unbound-variable` errors. If you need to access files outside the workspace (e.g. sibling directories or home directory), use GAIA tool functions (like `list-files`, `find-files` or `read-file`) with absolute paths instead of `run-in-sandbox`, as they will run on the host filesystem and trigger user-facing HITL prompts for approval.

# HOW TO WRITE CODE
- CRITICAL: ALL code and tool calls (like `llm-query`) that you want the system to AUTOMATICALLY execute in the REPL (to fetch data, run commands, or solve tasks) MUST be wrapped in a ```repl block!
- ILLUSTRATIONS & EXAMPLES: If you want to show the user a code example to read or copy-paste without running it automatically, wrap it in a ```scheme block. The system will NOT execute ```scheme blocks.
- Think in STATE: Variables you define in one step survive to the next.
Example of stateful reasoning:
Step 1:
```repl
(define my-files (git-ls-files))
(display (length my-files))
```
Step 2 (uses \"my-files\" from Step 1):
```repl
(define config-files (filter (lambda (f) (string-contains f \".yaml\")) my-files))
(display config-files)
```

The system will execute your code and return the output. You can then reason about the output and write more code.


# RESEARCH & DEBUGGING PROTOCOL
1. **Search Before You Leap**: If you are unsure about a function signature, return type, or which module to use,
   your FIRST step must be to use `(search-guile-manual \"pattern\")`.
2. **Handle Errors with Research**: If you encounter an `unbound-variable` error, DO NOT guess the name.
   Search the manual for the variable or feature you need to find the correct naming or the required module.
3. **Use Standard Modules**: Standard Guile modules like `(ice-9 ftw)` (for file tree walks) and `(ice-9 textual-ports)` are already available.
   Use `search-guile-manual` to learn how to use them instead of reinventing complex logic.
4. **POSIX Tools**: You have direct access to `stat`, `lstat`, `access`, and `file-exists?`. Use them for low-level file system logic.

# HYBRID RECURSION MODEL (llm-query vs. delegate)
If a task requires processing large files (logs), broad searches, or complex decoupled reasoning, you have two distinct ways to apply recursion:

1. IN-MEMORY SYNTHESIS & ANALYSIS:
   Use the Scheme procedure `(llm-query prompt)` inside your ```repl blocks to query a sub-LLM. Use this to summarize, analyze,
   or filter data already loaded into REPL variables (e.g. log contents, file lists).
   Example: `(define analysis (llm-query (string-append \"Analyze these logs: \" log-data)))`

2. INDEPENDENT SUB-AGENTS (DELEGATION):
   Use the `delegate` markdown block (OUTSIDE of ```repl blocks) to spawn a fresh, isolated agent to execute a parallel investigation
   (like reading separate folders, running searches, or fixing code).
   - Use a code block with language 'delegate' containing an S-expression: `(delegate \"Goal\" \"Context\")`.
   - WARNING: `delegate` IS NOT A SCHEME FUNCTION! DO NOT write it inside your ```repl blocks! It is a distinct markdown block
     used directly in your text response.
   - CRITICAL: The `delegate` block is parsed textually. It CANNOT access your Scheme variables!
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
6. SINGLE BLOCK: Only the LAST ```repl or ```wisp code block in your response will be executed.
   If you self-correct your thinking, make sure your final, intended code is in the last code block.
7. NO TRIVIAL DELEGATION: NEVER use `delegate` for summarizing, formatting, or translating text.
   You are fully capable of writing in the user's language. ONLY delegate for deep, isolated technical investigations.

# EXAMPLE TASK FLOW
User: \"Count .scm files in src/gaia/\"
Step 1 (GAIA writes code):
```repl
(define files (list-files \"src/gaia\"))
(define scm-files (filter (lambda (f) (string-suffix? \".scm\" f)) files))
(display (length scm-files))
```
Step 2 (System returns): \"8\"
Step 3 (GAIA answers):
The directory contains 8 .scm files.
FINAL(8)
CONFIDENCE(100)
")

(define (get-system-prompt)
  (let* ((base (if (get-config 'wisp-mode)
                   SYSTEM_PROMPT
                   (let* ((start (string-contains SYSTEM_PROMPT "- **Wisp (SRFI-119) Support:**"))
                          (end (string-contains SYSTEM_PROMPT "# PRE-LOADED MODULES")))
                     (if (and start end)
                         (string-append (substring SYSTEM_PROMPT 0 start)
                                        (substring SYSTEM_PROMPT end))
                         SYSTEM_PROMPT))))
         ;; Strip FINAL/CONFIDENCE signals from notebook prompt — they belong to solver only
         ;; Remove CRITICAL RULE 1 about FINAL
         (cleaned (regexp-substitute/global #f
                    "1\\. NEVER put FINAL\\(\\) or FINAL_VAR\\(\\) in the same response as a ```repl code block![^\n]*\n[^\n]*\n[^\n]*\n"
                    base 'pre "" 'post))
         ;; Remove example FINAL/CONFIDENCE lines
         (cleaned (regexp-substitute/global #f "FINAL\\([^)]*\\)\n" cleaned 'pre "" 'post))
         (cleaned (regexp-substitute/global #f "CONFIDENCE\\([^)]*\\)\n" cleaned 'pre "" 'post))
         ;; Add notebook-specific instructions before CRITICAL RULES
         (insert-idx (string-contains cleaned "# CRITICAL RULES"))
         (notebook-instructions
           (string-append
            "# INTERACTIVE NOTEBOOK MODE\n"
            "You are operating in an interactive notebook mode. When you write a ```repl code block:\n"
            "1. The system will AUTOMATICALLY execute it and show the result or error inline.\n"
            "2. If the code produces an error, the system will ask you to fix it. Analyze the error carefully and provide corrected code.\n"
            "3. After successful execution, the result is shown to the user. Do NOT repeat or summarize the result.\n"
            "4. Do NOT use FINAL(), FINAL_VAR(), or CONFIDENCE() signals — those are only for the solver mode.\n"
            "5. Keep your responses concise. Explain what the code does briefly, then write the code.\n\n")))
    (if insert-idx
        (string-append (substring cleaned 0 insert-idx)
                        notebook-instructions
                        (substring cleaned insert-idx))
        (string-append cleaned "\n" notebook-instructions))))


(define (get-solver-system-prompt)
  (let* ((base (get-system-prompt))
         (insert-idx (string-contains base "# RESEARCH & DEBUGGING PROTOCOL")))
    (if insert-idx
        (string-append (substring base 0 insert-idx)
                       "\n# COMPLETION SIGNALS\n"
                       "When you have solved the task COMPLETELY, use ONE of these signals:\n"
                       "- `FINAL(answer)` — For direct text answers. Example: `FINAL(The file contains 42 errors)`\n"
                       "- `FINAL_VAR(variable_name)` — For answers stored in a variable from code execution.\n\n"
                       "After each step, rate your confidence:\n"
                       "- `CONFIDENCE(score)` — 0-100%. If >= 95%, the system stops automatically.\n\n"
                       (substring base insert-idx))
        (string-append base
                       "\n# COMPLETION SIGNALS\n"
                       "When you have solved the task COMPLETELY, use ONE of these signals:\n"
                       "- `FINAL(answer)` — For direct text answers. Example: `FINAL(The file contains 42 errors)`\n"
                       "- `FINAL_VAR(variable_name)` — For answers stored in a variable from code execution.\n\n"
                       "After each step, rate your confidence:\n"
                       "- `CONFIDENCE(score)` — 0-100%. If >= 95%, the system stops automatically.\n\n"))))

(define (string-contains-last str pattern)
  (let loop ((start 0)
             (last-idx #f))
    (let ((idx (string-contains str pattern start)))
      (if idx
          (loop (+ idx (string-length pattern)) idx)
          last-idx))))

(define (extract-code response)
  "Extracts Scheme or Wisp code from the LLM response.
Prefers the LAST code block (either ```repl or ```wisp) to support LLM self-correction patterns."
  (let ((str (if (string? response) response (scm->json response))))
    (let* ((repl-idx (string-contains-last str "```repl"))
           (wisp-idx (string-contains-last str "```wisp"))
           (block-info (cond
                        ((and repl-idx wisp-idx)
                         (if (> repl-idx wisp-idx)
                             (cons repl-idx 'repl)
                             (cons wisp-idx 'wisp)))
                        (repl-idx (cons repl-idx 'repl))
                        (wisp-idx (cons wisp-idx 'wisp))
                        (else #f))))
      (if block-info
          (let* ((idx (car block-info))
                 (type (cdr block-info))
                 (start (+ idx 7))
                 (end (string-contains str "```" start))
                 (raw-code (if end (substring str start end) #f)))
            (if raw-code
                ;; Clean any FINAL(N) or CONFIDENCE(N) that small models mistakenly put inside code blocks
                (let* ((cleaned (regexp-substitute/global #f "FINAL\\([^)]*\\)" raw-code 'pre "" 'post))
                       (cleaned (regexp-substitute/global #f "CONFIDENCE\\([^)]*\\)" cleaned 'pre "" 'post))
                       (trimmed (string-trim-both cleaned)))
                  (if (> (string-length trimmed) 0)
                      (if (eq? type 'wisp)
                          (string-append ";; wisp\n" trimmed)
                          trimmed)
                      #f))
                #f))
          #f))))

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

(define (handle-error error-type message code depth)
  "Generates contextual feedback for errors."
  (match error-type
    ((or 'syntax 'parse-error 'syntax-error)
     (let* ((analysis (analyze-parentheses code))
            (hint (cdr analysis)))
       (string-append "Syntax Error in your Scheme code: " message
                      (if hint (string-append "\n" hint) "")
                      "\nPlease check parentheses and syntax. Remember: use (use-modules ...) NOT require.")))
    ('permission
     (string-append "Security Violation: " message "\nYou must use only allowed primitives. Use the pre-loaded tools from (gaia tools) instead."))
    ('runtime
     (string-append "Runtime Error: " message "\nReview the logic and try debugging with display statements."))
    (_
     (string-append "Unknown Error: " message))))

(define MAX-RECURSION-DEPTH 15)
(define CONFIDENCE-THRESHOLD 95)

(define (get-trajectory-file session-id)
  (let ((env-file (getenv "GAIA_TRAJECTORIES_FILE")))
    (if env-file
        env-file
        (string-append "trajectories-" session-id ".jsonl"))))

(define* (rlm-loop session-id last-output depth history #:optional (env (make-rlm-env)) #:key (event-handler #f) (permission-handler #f))
  "The core RLM loop. Maintains a persistent environment across iterations."
  (rlm-inject! env 'llm-query
    (lambda (prompt)
      (let* ((sub-session (string-append session-id "-sub-" (number->string (random 1000000000))))
             (response (chat-with-llm sub-session prompt (get-config 'model) (or (get-config 'system-prompt) SYSTEM_PROMPT) #:history history))
             (payload (assoc-ref response "payload")))
        (if payload
            (assoc-ref payload "content")
            "Error: No response from sub-LLM"))))
  (rlm-inject! env 'context last-output)

  (rlm-loop-inner session-id last-output depth env history 1 '() #:event-handler event-handler #:permission-handler permission-handler))

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
  "Format transcript entries as a compact execution log with Step Compaction to prevent Context Rot."
  (let* ((step-entries (filter (lambda (entry)
                                 (let ((role (car entry)))
                                   (or (string=? role "user") (string=? role "assistant"))))
                               transcript))
         (total-steps (inexact->exact (round (/ (length step-entries) 2))))
         (compaction-threshold 4)
         (step-num 0))
    (if (<= total-steps compaction-threshold)
        ;; No compaction needed
        (string-join
         (filter-map
          (lambda (entry)
            (let ((role (car entry))
                  (text (cdr entry)))
              (cond
               ((string=? role "user")
                (set! step-num (+ step-num 1))
                (string-append "[Step " (number->string step-num) " input] " text))
               ((string=? role "assistant")
                (string-append "[Step " (number->string step-num) " response] " (truncate-for-transcript text)))
               (else #f))))
          transcript)
         "\n")
        ;; Perform Step Compaction!
        ;; We summarize the first (total-steps - 3) steps, and show the last 3 steps in full.
        (let* ((steps-to-compact (- total-steps 3))
               (compacted-count (* steps-to-compact 2))
               (compacted-entries (take step-entries compacted-count))
               (remaining-entries (drop step-entries compacted-count))
               (summary-text
                (format #f "[Steps 1-~a summarized: Successful execution of Scheme REPL operations and exploratory commands. Defined variables and functions survive permanently in Goblins sandbox memory.]"
                        steps-to-compact)))
          (set! step-num steps-to-compact)
          (string-join
           (cons summary-text
                 (filter-map
                  (lambda (entry)
                    (let ((role (car entry))
                          (text (cdr entry)))
                      (cond
                       ((string=? role "user")
                        (set! step-num (+ step-num 1))
                        (string-append "[Step " (number->string step-num) " input] " text))
                       ((string=? role "assistant")
                        (string-append "[Step " (number->string step-num) " response] " (truncate-for-transcript text)))
                       (else #f))))
                  remaining-entries))
           "\n")))))

(define (strip-tag text start-tag end-tag)
  (let loop ((t text))
    (let ((start (string-contains t start-tag))
          (end (string-contains t end-tag)))
      (cond
       ((and start end (> end start))
        (loop (string-append (substring t 0 start)
                             (substring t (+ end (string-length end-tag))))))
       (start
        (substring t 0 start))
       (end
        (string-append (substring t 0 end) (substring t (+ end (string-length end-tag)))))
       (else t)))))

(define (strip-code-blocks text)
  (let loop ((t text))
    (let ((start (string-contains t "```")))
      (if start
          (let ((end (string-contains t "```" (+ start 3))))
            (if end
                (loop (string-append (substring t 0 start)
                                     (substring t (+ end 3))))
                (substring t 0 start)))
          t))))

(define (strip-macros text)
  (let* ((t (regexp-substitute/global #f (make-regexp "FINAL_VAR\\s*\\([^)]*\\)" regexp/icase) text 'pre "" 'post))
         (t (regexp-substitute/global #f (make-regexp "FINAL\\s*\\([^)]*\\)" regexp/icase) t 'pre "" 'post))
         (t (regexp-substitute/global #f (make-regexp "CONFIDENCE\\s*\\([^)]*\\)" regexp/icase) t 'pre "" 'post))
         (t (regexp-substitute/global #f (make-regexp "CONFIDENCE:\\s*[0-9]+%?" regexp/icase) t 'pre "" 'post))
         (t (regexp-substitute/global #f (make-regexp "CONFIDENCE\\s+[0-9]+%?" regexp/icase) t 'pre "" 'post))
         (t (regexp-substitute/global #f (make-regexp "Final Answer:\\s*.*" regexp/icase) t 'pre "" 'post)))
    t))

(define (strip-internal-tokens text)
  (let* ((t (regexp-substitute/global #f "<channel\\|>" text 'pre "" 'post))
         (t (regexp-substitute/global #f "<unused87>tool_code" t 'pre "" 'post))
         (t (regexp-substitute/global #f "<unused88>" t 'pre "" 'post)))
    t))

(define (clean-assistant-content text)
  "Strips thinking blocks, confidence scores, final signals, code blocks and internal tokens."
  (if (not (string? text))
      ""
      (let* ((t text)
             (t (strip-tag t "<think>" "</think>"))
             (t (strip-tag t "<|think|>" "</|think|>"))
             (t (strip-tag t "<thought>" "</thought>"))
             (t (strip-tag t "<confidence>" "</confidence>"))
             (t (strip-code-blocks t))
             (t (strip-macros t))
             (t (strip-internal-tokens t)))
        (string-trim-both t))))

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

(define* (rlm-loop-inner session-id last-output depth env history step transcript #:key (event-handler #f) (permission-handler #f))
  (let ((prompt last-output))
    (when event-handler (event-handler `(status ,(format #f "Agent Depth ~a (Step ~a)..." depth step))))
    (check-interrupt!)
    (if (> depth MAX-RECURSION-DEPTH)
        (begin
          (gaia-log "\n[GAIA] Max recursion depth reached. Returning current state.\n")
          (cons last-output history))
        (begin
          (gaia-log (string-append C-GREY "\n[GAIA] Agent Depth " (number->string depth) " (Step " (number->string step) ")..." C-RESET "\n"))
          (let* ((response (catch #t
                            (lambda ()
                              (chat-with-llm session-id prompt (get-config 'model) (or (get-config 'system-prompt) SYSTEM_PROMPT)
                                             #:think (get-config 'thinking)
                                             #:history history
                                             #:role "user"
                                             #:stream-callback (lambda (evt)
                                                                 (when event-handler
                                                                   (event-handler evt)))))
                            (lambda (key . args)
                              (when (eq? key 'user-interrupt) (apply throw key args))
                              (when *interrupted*
                                (set! *interrupted* #f)
                                (throw 'user-interrupt))
                              (apply throw key args))))
                 (_ (check-interrupt!))
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

              (let ((log-entry `(("session_id" . ,session-id)
                                 ("prompt" . ,prompt)
                                 ("input" . ,last-output)
                                 ("response" . ,response-text)
                                 ("reasoning" . ,reasoning-text)
                                 ("timestamp" . ,(number->string (current-time)))
                                 ("confidence" . ,(if conf-val conf-val "null"))
                                 ("final_signal" . ,(if final-sig "true" "false")))))
                (let ((port (open-file (get-trajectory-file session-id) "a")))
                  (display (scm->json log-entry) port)
                  (newline port)
                  (close-port port)))

              (if (string=? response-text "")
                  (begin
                    (gaia-log (string-append C-RED "\n[GAIA] Empty response from model. Retrying..." C-RESET "\n"))
                    (let ((retry-transcript
                           (if (= step 1)
                               (list (cons "original-task" last-output)
                                     (cons "user" last-output)
                                     (cons "assistant" "(empty response)"))
                               (append transcript
                                       (list (cons "user" last-output)
                                             (cons "assistant" "(empty response)"))))))
                      (rlm-loop-inner session-id
                                      "Your previous response was empty. Please write a ```repl code block to continue working on the task, \
or provide FINAL(answer) if you have the answer."
                        depth env
                        (append history
                                       (list `(("role" . "assistant") ("content" . "(empty response)"))))
                        (+ step 1) retry-transcript #:event-handler event-handler #:permission-handler permission-handler)))

                  (let ((updated-transcript
                     (append transcript
                             (if (= step 1)
                                 (list (cons "original-task" last-output)
                                       (cons "assistant" (truncate-for-transcript response-text))
                                       (cons "user" last-output))
                                 (list (cons "user" last-output)
                                       (cons "assistant" (truncate-for-transcript response-text)))))))

                (when (and reasoning-text (> (string-length reasoning-text) 0))
                  (when event-handler (event-handler `(thought-full ,reasoning-text)))
                  (gaia-log (string-append C-GREY "[GAIA] Thinking asynchronously... (See monitor)" C-RESET "\n")))

        (let ((prose (clean-assistant-content response-text)))
                  (when (> (string-length prose) 0)
                    (when event-handler (event-handler `(analysis ,prose)))
                    (gaia-log (string-append C-BLUE "\n[GAIA] Analysis: " C-RESET (markdown->ansi prose) "\n"))))

                (let ((action-code (extract-code response-text))
                      (action-delegate (extract-delegation response-text)))
                  (cond
                   (action-delegate =>
                    (lambda (delegation)
                      (match delegation
                        (('delegate goal context-str)
                         (gaia-log (string-append C-BOLD C-YELLOW "\n[GAIA] Spawning Sub-Agent (Delegation):\n" C-RESET "Goal: " goal "\nContext: " context-str "\n"))
                         (let* ((sub-session-id (string-append session-id "-sub-" (number->string (random 1000000000))))
                                (initial-input (string-append "GOAL: " goal "\nCONTEXT: " context-str))
                                (sub-res-pair (rlm-loop sub-session-id initial-input (+ depth 1)
                                                      (append history (list `(("role" . "user") ("content" . ,last-output))
                                                                            `(("role" . "assistant") ("content" . ,response-text))))
                                                      #:event-handler event-handler #:permission-handler permission-handler))
                                (sub-result (car sub-res-pair)))
                           (gaia-log (string-append C-BOLD C-GREEN "\n[GAIA] Sub-Agent completed.\n" C-RESET "Result length: "
                                                   (number->string (string-length sub-result)) " chars\n"))
                           (if final-sig
                               (cons (match final-sig (('final ans) ans) (('final-var var) var) (_ "Sub-agent executed successfully"))
                                     (append history (list `(("role" . "user") ("content" . ,last-output))
                                                           `(("role" . "assistant") ("content" . ,response-text)))))
                               (rlm-loop-inner session-id (string-append "[System Sub-agent]:\nSub-agent execution finished. Result: " sub-result)
                                               depth env
                                               (append history (list `(("role" . "user") ("content" . ,last-output))
                                                                     `(("role" . "assistant") ("content" . ,response-text))))
                                               (+ step 1) updated-transcript #:event-handler event-handler #:permission-handler permission-handler))))
                        (_
                         (rlm-loop-inner session-id "[System Error]:\nInvalid delegation format. Use (delegate \"Goal\" \"Context\")"
                                         depth env
                                         (append history (list `(("role" . "user") ("content" . ,last-output))
                                                               `(("role" . "assistant") ("content" . ,response-text))))
                                         (+ step 1) updated-transcript #:event-handler event-handler #:permission-handler permission-handler)))))

                   (action-code =>
                    (lambda (code)
                      (if (and code (> (string-length code) 0) (not (string=? code response-text)))
                          (begin
                            (when event-handler (event-handler `(code ,code)))
                            (gaia-log (string-append C-BOLD C-CYAN "\n[GAIA] Executing Scheme Code:\n" C-RESET code "\n"))
                            (match (rlm-execute env code #:permission-handler permission-handler)
                              (('ok result)
                               (when event-handler (event-handler `(result ,result)))
                               (gaia-log (string-append C-GREEN "\n[REPL] Success:\n" C-RESET result "\n"))
                               (rlm-loop-inner session-id (string-append "[System REPL Output]:\nCode executed successfully. Result:\n" result)
                                               depth env
                                               (append history
                                                       (list `(("role" . "user") ("content" . ,last-output))
                                                             `(("role" . "assistant") ("content" . ,response-text))))
                                               (+ step 1) updated-transcript #:event-handler event-handler #:permission-handler permission-handler))
                              (('error et msg . rest)
                               (let ((feedback (handle-error et msg code depth)))
                                 (when event-handler (event-handler `(repl-error ,feedback)))
                                 (gaia-log (string-append C-RED "\n[REPL] Runtime Error:\n" C-RESET feedback "\n"))
                                 (rlm-loop-inner session-id (string-append "[System Error]:\n" feedback) depth env
                                                 (append history (list `(("role" . "user") ("content" . ,last-output))
                                                                       `(("role" . "assistant") ("content" . ,response-text))))
                                                 (+ step 1) updated-transcript #:event-handler event-handler #:permission-handler permission-handler)))))
                          (cons response-text (append history (list `(("role" . "user") ("content" . ,last-output))
                                                                    `(("role" . "assistant") ("content" . ,response-text))))))))

                   ((and final-sig (match final-sig (('final ans) ans) (('final-var var) var) (_ #f))) =>
                    (lambda (answer)
                      (when event-handler (event-handler `(final ,answer)))
                      (if (equal? (car final-sig) 'final)
                          (gaia-log (string-append C-BOLD "[GAIA] Final Answer: " C-RESET (markdown->ansi answer) "\n"))
                          (gaia-log (string-append C-BOLD "[GAIA] Answer stored in: " C-RESET answer "\n")))
                      (cons answer (append history (list `(("role" . "user") ("content" . ,last-output))
                                                         `(("role" . "assistant") ("content" . ,response-text)))))))

                   ((and conf-val (>= conf-val CONFIDENCE-THRESHOLD))
                    (when event-handler (event-handler `(final ,response-text)))
                    (gaia-log (string-append C-GREEN "\n[GAIA] ✓ High confidence (" (number->string conf-val) "%) - stopping." C-RESET "\n"))
                    (cons response-text (append history (list `(("role" . "user") ("content" . ,last-output))
                                                              `(("role" . "assistant") ("content" . ,response-text))))))

                   (else
                    (when event-handler (event-handler `(final ,response-text)))
                    (gaia-log (string-append C-RED "\n[GAIA] ⚠ No actionable output. Treating as final answer (unless low confidence)." C-RESET "\n"))
                    (cons response-text (append history (list `(("role" . "user") ("content" . ,last-output))
                                                              `(("role" . "assistant") ("content" . ,response-text))))))))))))))))

(define (handle-command input session-id history env)
  "Parses and executes meta-commands or delegates to RLM.
Returns (list updated-history updated-env should-continue?)"
  (cond
   ;; /exit
   ((string=? input "/exit")
    (display "Bye.\n")
    (list history env #f))

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
    (display "  /env           - Show variables defined in the current REPL session\n")
    (display "  /help          - Show this help\n")
    (display "  /exit          - Quit GAIA\n")
    (display "  <query>        - Start standard RLM investigation\n")
    (list history env #t))

   ;; /clear
   ((string=? input "/clear")
    (display (string-append C-YELLOW "Conversation history and REPL environment cleared." C-RESET "\n"))
    (list '() (make-rlm-env) #t))

   ;; /env
   ((string=? input "/env")
    (let ((bindings (rlm-env-user-bindings env)))
      (display (string-append C-BOLD "User-defined REPL Bindings:\n" C-RESET))
      (if (null? bindings)
          (display "  (empty)\n")
          (for-each (lambda (b)
                      (display (format #f "  ~a = ~a\n" (car b) (cdr b))))
                    bindings)))
    (list history env #t))

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
        (list (append history (list `(("role" . "user") ("content" . ,query))
                                    `(("role" . "assistant") ("content" . ,content))))
              env #t))))

   ;; /eval <scheme>
   ((string-prefix? "/eval " input)
    (let ((code (substring input 6)))
      (match (rlm-execute env code)
        (('ok result)
         (display (string-append C-GREEN "[REPL] Success:\n" C-RESET result "\n")))
        (('error type msg)
         (display (string-append C-RED "[REPL] Error (" (symbol->string type) "):\n" C-RESET msg "\n"))))
      (list history env #t)))

   ;; /models
   ((string=? input "/models")
    (let ((models-list (get-models)))
       (display (string-append C-BOLD "Available models (from LLM Registry):\n" C-RESET))
       (if (list? models-list)
           (for-each (lambda (m) (display (string-append "  - " m "\n"))) models-list)
           (display (string-append C-RED "  No models found or unexpected response format.\n" C-RESET))))
    (list history env #t))

   ;; /model
   ((string=? input "/model")
    (display (string-append C-BOLD "Current model: " C-RESET (get-config 'model) "\n"))
    (list history env #t))

   ;; /model <name>
   ((string-prefix? "/model " input)
    (let ((new-model (substring input 7)))
       (set-config! 'model new-model)
       (display (string-append C-GREEN "Model hot-swapped for session to: " C-RESET new-model "\n")))
    (list history env #t))

   ;; /thinking
   ((string=? input "/thinking")
    (display (string-append "Current thinking mode: " (if (get-config 'thinking) "ON" "OFF") "\n"))
    (list history env #t))

   ;; /thinking <on/off>
   ((string-prefix? "/thinking " input)
    (let ((arg (string-trim-both (substring input 10))))
      (cond
       ((or (string=? arg "on") (string=? arg "1"))
        (set-config! 'thinking #t)
        (display (string-append C-CYAN "Thinking mode ENABLED." C-RESET "\n")))
       ((or (string=? arg "off") (string=? arg "0"))
        (set-config! 'thinking #f)
        (display (string-append C-YELLOW "Thinking mode DISABLED." C-RESET "\n")))
       (else
        (display (string-append "Current thinking mode: " (if (get-config 'thinking) "ON" "OFF") "\n"))))
      (list history env #t)))

   ;; /base-model
   ((string=? input "/base-model")
    (display (string-append C-BOLD "Current base model for training: " C-RESET (get-config 'base-model) "\n"))
    (list history env #t))

   ;; /base-model <name>
   ((string-prefix? "/base-model " input)
    (let ((new-base (substring input 12)))
       (set-config! 'base-model new-base)
       (display (string-append C-GREEN "Base model for training hot-swapped to: " C-RESET new-base "\n")))
    (list history env #t))

   ;; /train
   ((string=? input "/train")
    (display (string-append C-YELLOW "Triggering model training...\n" C-RESET))
    (let ((current-base (get-config 'base-model)))
      (setenv "GAIA_BASE_MODEL" current-base)
      (system* "make" "learn")
      (setenv "GAIA_BASE_MODEL" ""))
    (list history env #t))

   ;; Standard RLM Loop
   (else
   (let* ((res-pair (rlm-loop session-id input 0 history env #:event-handler #f #:permission-handler #f))
          (answer (car res-pair))
          (new-history (cdr res-pair)))
     (list new-history env #t)))))

(define (start-gaia . args)
  (activate-readline)
  (display (string-append C-BOLD C-GREEN "Initializing GAIA (GNU AI Assistant)..." C-RESET "\n"))

  ;; Handle Ctrl-C: set flag AND throw.
  ;; Flag alone doesn't work because Guile's C I/O retries on EINTR,
  ;; so http-post stays blocked. Throw breaks out of C code.
  ;; Flag is backup for safe-point checks when throw gets lost.
  (sigaction SIGINT (lambda (sig)
                      (set! *interrupted* #t)
                      (gaia-log (string-append C-RED "\n[GAIA] Interrupt received. Returning to prompt..." C-RESET "\n"))
                      (throw 'user-interrupt)))

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

    (let loop ((chat-history '())
               (global-env (make-rlm-env)))
      (newline)
      (catch 'user-interrupt
        (lambda ()
          (let ((input (readline (string-append "\x01" C-BOLD C-GREEN "\x02(GAIA) >\x01" C-RESET "\x02 "))))
            (cond
             ((eof-object? input) (newline))
             ((string=? input "") (loop chat-history global-env))
             (else
              (add-history input) ;; Add to readline history
              (let* ((result (handle-command input session-id chat-history global-env))
                     (new-history (car result))
                     (new-env (cadr result))
                     (continue? (caddr result)))
                (if continue?
                    (loop new-history new-env)
                    #t))))))
        (lambda _
          (set! *interrupted* #f)  ;; Reset flag
          (gaia-log (string-append C-YELLOW "\n[GAIA] Task interrupted by user. State preserved." C-RESET "\n"))
          (loop chat-history global-env))))))
