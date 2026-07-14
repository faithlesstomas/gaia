(define-module (gaia executor)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 format)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-13)  ;; Strings
  #:use-module (ice-9 threads)
  #:use-module (gaia rlm-env)
  #:use-module (gaia sandbox)
  #:export (guix-investigate rlm-execute))

(define CAPABILITY-DOCS
  '((read-file . "(read-file path) -> string\nReads and returns the contents of the file at PATH.")
    (write-file . "(write-file path content) -> void\nWrites CONTENT string to the file at PATH.")
    (delete-file . "(delete-file path) -> void\nDeletes the file at PATH.")
    (list-files . "(list-files path) -> list of strings\nLists all files and directories in PATH.")
    (run-command . "(run-command cmd-string) -> string\nRuns a terminal command in the sandbox. Requires HITL approval for non-whitelisted commands.")
    (patch-file . "(patch-file path old-string new-string) -> boolean\nReplaces OLD-STRING with NEW-STRING in the file at PATH.")
    (read-files . "(read-files path-list) -> list of (path . content)\nBatch reads multiple files at once.")
    (map-files . "(map-files dir pattern proc) -> void\nApplies procedure PROC to all files in DIR matching PATTERN.")
    (find-files . "(find-files dir pattern) -> list of strings\nFinds files matching PATTERN recursively starting from DIR.")
    (git-status . "(git-status) -> string\nRuns 'git status' in the workspace.")
    (git-diff . "(git-diff) -> string\nRuns 'git diff' in the workspace.")
    (git-log . "(git-log) -> string\nRuns 'git log' in the workspace.")
    (git-ls-files . "(git-ls-files) -> string\nLists tracked files in the git repository.")
    (system . "(system cmd) -> integer\nRuns CMD in a shell (returns exit status).")
    (system* . "(system* cmd arg1 ...) -> integer\nRuns CMD with ARGs directly (returns exit status).")
    (run-python . "(run-python code) -> string\nEvaluates Python code in a persistent Python process sandbox.")
    (search-file . "(search-file path pattern) -> list of strings\nSearches for PATTERN in file at PATH.")
    (search-guile-manual . "(search-guile-manual query) -> string\nSearches Guile documentation for QUERY.")
    (run-sed . "(run-sed path old-regex new-regex) -> void\nRuns sed-like regex replacement in-place on file at PATH.")
    (run-awk . "(run-awk path script) -> string\nRuns awk script on file at PATH.")
    (file-info . "(file-info path) -> list\nReturns metadata/stat for file at PATH.")
    (guix-search . "(guix-search query) -> string\nSearches Guix packages for QUERY.")
    (guix-package-info . "(guix-package-info pkg) -> string\nGets description and info for Guix package PKG.")
    (get-system-logs . "(get-system-logs) -> string\nRetrieves system logs.")
    (get-recent-logs . "(get-recent-logs) -> string\nRetrieves recent system logs.")
    (get-boot-logs . "(get-boot-logs) -> string\nRetrieves system boot logs.")
    (list-boots . "(list-boots) -> string\nLists system boot records.")
    (get-kernel-logs . "(get-kernel-logs) -> string\nRetrieves kernel/dmesg logs.")
    (fork-sandbox . "(fork-sandbox) -> sandbox\nClones the current sandbox state.")
    ))

(define (rlm-lookup-doc env sym)
  (let* ((custom-doc (assoc-ref CAPABILITY-DOCS sym)))
    (if custom-doc
        (list 'ok custom-doc)
        (let* ((sandbox (rlm-env-sandbox env))
               (m (sandbox-module sandbox))
               (val (catch #t
                      (lambda () (module-ref m sym #f))
                      (lambda _ #f))))
          (cond
           ((not val)
            (list 'ok (format #f "Symbol '~a' is not defined in the sandbox." sym)))
           ((procedure? val)
            (let ((doc (procedure-documentation val)))
              (list 'ok (format #f "Procedure '~a': ~a"
                                sym
                                (or doc "No documentation/docstring available.")))))
           (else
            (list 'ok (format #f "Variable '~a' (value: ~a)" sym val))))))))

(define* (rlm-execute env code-string #:key (permission-handler #f))
  "Executes code in the persistent RLM environment inside a POSIX thread
to prevent blocking the Fibers scheduler, yielding control cooperatively."
  (let ((trimmed (string-trim-both code-string)))
    (cond
     ((string-prefix? ",help" trimmed)
      (let* ((rest (string-trim-both (substring trimmed 5)))
             (parts (string-split rest #\space))
             (sym-str (if (null? parts) "" (car parts))))
        (if (not (string-null? sym-str))
            (rlm-lookup-doc env (string->symbol sym-str))
            (list 'ok "Available REPL meta-commands:\n  ,help          - Show this help\n  ,help <symbol> - Show documentation for <symbol> (alias: ,doc <symbol>)\n  ,doc <symbol>  - Show documentation for <symbol>\n  ,bindings      - Show current user-defined variables and their values\n  ,globals       - Show all whitelisted sandbox functions and capability procedures\n"))))
     ((string-prefix? ",doc" trimmed)
      (let* ((rest (string-trim-both (substring trimmed 4)))
             (parts (string-split rest #\space))
             (sym-str (if (null? parts) "" (car parts))))
        (if (not (string-null? sym-str))
            (rlm-lookup-doc env (string->symbol sym-str))
            (list 'ok "Usage: ,doc <symbol> - Show documentation for a specific symbol.\n"))))
     ((string=? trimmed ",bindings")
      (let ((bindings (rlm-env-user-bindings env)))
        (if (null? bindings)
            (list 'ok "No user bindings defined.")
            (list 'ok (string-join (map (lambda (b)
                                          (format #f "  ~a = ~a" (car b) (cdr b)))
                                        bindings)
                                   "\n")))))
     ((string=? trimmed ",globals")
      (let* ((caps CAPABILITY-NAMES)
             (exports SAFE-GUILE-EXPORTS)
             (caps-str (string-join (map symbol->string caps) ", "))
             (exports-str (string-join (map symbol->string exports) ", ")))
        (list 'ok (format #f "Safe Guile Primitives:\n  ~a\n\nGAIA Capability Procedures:\n  ~a\n"
                          exports-str caps-str))))
     (else
      (let* ((result-val #f)
             (result-err #f)
             (done? #f)
             (worker (call-with-new-thread
                      (lambda ()
                        (catch #t
                          (lambda ()
                            (set! result-val (rlm-eval! env code-string #:permission-handler permission-handler)))
                          (lambda (key . args)
                            (set! result-err (cons key args))))
                        (set! done? #t)))))
        (let ((interrupted? (lambda ()
                              (module-ref (resolve-module '(gaia core)) '*interrupted*)))
              (fibers-sleep (lambda (t)
                              (let ((sleep-proc (catch #t
                                                  (lambda ()
                                                    (module-ref (resolve-module '(fibers) #:ensure #f) 'sleep))
                                                  (lambda _ #f))))
                                (if sleep-proc
                                    (sleep-proc t)
                                    (usleep (inexact->exact (round (* t 1000000)))))))))
          (let loop ()
            (cond
             ((interrupted?)
              (cancel-thread worker)
              (throw 'user-interrupt))
             (done?
              (if result-err
                  (apply throw (car result-err) (cdr result-err))
                  result-val))
             (else
              (fibers-sleep 0.01)
              (loop))))))))))

(define BANNED-PRIMITIVES '(system system* delete-file rmdir rename-file chmod))

(define (validate-safety sexp)
  "Recursively checks S-expression for banned primitives. Returns #t if safe, or an error string."
  (cond
   ((pair? sexp)
    (let ((head (car sexp))
          (tail (cdr sexp)))
      (if (and (symbol? head) (memq head BANNED-PRIMITIVES))
          (format #f "Security Violation: Usage of banned primitive '~a' is not allowed." head)
          (let ((head-res (validate-safety head)))
            (if (string? head-res)
                head-res
                (validate-safety tail))))))
   ;; Atoms (symbols, numbers, strings, etc.) are always safe
   (else #t)))

(define *guix-container-supported* #t)
(define *guix-checked* #f)

(define (guix-container-supported?)
  (unless *guix-checked*
    (let* ((pipe (open-input-pipe "guix shell --container coreutils -- echo guix-container-ok 2>&1"))
           (res (read-string pipe)))
      (close-pipe pipe)
      (set! *guix-container-supported*
            (and (string? res)
                 (string-contains res "guix-container-ok")
                 #t))
      (set! *guix-checked* #t)))
  *guix-container-supported*)

(define (guix-investigate s-expression-code)
  "Executes the given S-expression code inside a guix shell container if supported, falling back locally otherwise."
  (let* ((wrapped-str (format #f "(begin ~a)" s-expression-code))
         ;; Parse locally to validate
         (parsed-sexp (catch #t
                             (lambda () (with-input-from-string wrapped-str read))
                             (lambda _ #f))))

    (if (not parsed-sexp)
        (list 'error 'syntax "Error: Could not parse code (Syntax Error).")
        (let ((safety-result (validate-safety parsed-sexp)))
          (if (string? safety-result)
              (list 'error 'permission safety-result) ;; Return security error
              ;; Proceed with execution if safe
              (let* ((char-codes (map char->integer (string->list wrapped-str)))
                     (codes-str (string-join (map number->string char-codes) " "))
                     ;; We wrap the code to run inside our sandbox module
                     ;; We assume /workspace maps to project root, so 'scheme' dir is at /workspace/src
                     (container-command
                      (format #f
                             "(begin (add-to-load-path \"/workspace/src\") (add-to-load-path \"src\") (use-modules (gaia sandbox) (ice-9 match)) (let* ((sb (make-sandbox \"investigate\" #f (lambda (expr) #t))) (code-str (list->string (map integer->char '(~a)))) (res (sandbox-eval sb code-str))) (match res (('ok val) (display val)) (('error type msg) (display (format #f \"Error: ~~a ~~a\" type msg))))))"
                              codes-str))

                     ;; Helper to shell-quote a string (wrap in single quotes, escape inner single quotes)
                     (shell-quote (lambda (s) (string-append "'" (string-join (string-split s #\') "'\\''") "'")))

                     (process-result
                      (lambda (res)
                        (if (string-prefix? "Error: " res)
                            (let* ((stripped (substring res 7))
                                   (space-idx (string-index stripped #\space))
                                   (err-type (string->symbol (substring stripped 0 space-idx)))
                                   (err-msg (substring stripped (+ space-idx 1))))
                              (list 'error err-type err-msg))
                            (list 'ok res))))

                     ;; Level 1: Guile command runs code
                     (guile-cmd-inner (format #f "guile --no-auto-compile -c ~a" (shell-quote container-command)))

                     ;; Level 2: Bash command runs guile command
                     (bash-cmd (format #f "bash -c ~a" (shell-quote guile-cmd-inner))))

                (if (guix-container-supported?)
                    ;; Level 3: Guix Shell executes bash
                    (let* ((command (format #f "guix shell --container --share=./=/workspace guile guile-json guile-fibers guile-goblins guile-wisp coreutils grep sed gawk bash git guix texinfo gzip -- ~a" bash-cmd))
                           (port (open-input-pipe command))
                           (result (read-string port))
                           (exit-val (status:exit-val (close-pipe port))))
                      (if (eq? exit-val 0)
                          (process-result result)
                          (list 'error 'runtime (string-append "Error: Execution failed with exit code " (number->string exit-val)
                                                               "\nOutput:\n" result))))
                    ;; Fallback to local execution since guix shell container is restricted in this environment
                    (let* ((local-cmd (format #f "guile --no-auto-compile -L src -c ~a" (shell-quote container-command)))
                           (l-port (open-input-pipe local-cmd))
                           (l-res (read-string l-port))
                           (l-exit (status:exit-val (close-pipe l-port))))
                      (if (eq? l-exit 0)
                          (process-result l-res)
                          (list 'error 'runtime (string-append "Error: Execution failed with exit code " (number->string l-exit)
                                                               "\nOutput:\n" l-res)))))))))))
