(define-module (gaia sandbox)
  #:use-module (ice-9 match)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)   ;; Records
  #:use-module (srfi srfi-13)  ;; Strings
  #:use-module (language wisp spec)
  #:use-module (system base language)
  #:use-module (gaia tools)
  #:export (make-sandbox
            sandbox-eval
            sandbox-definitions
            fork-sandbox
            run-python-in-sandbox
            auto-heal-escape-sequences
            sandbox-module
            sandbox-initial-symbols
            backup-module
            restore-module!))

(define (safe-path? path)
  (and (not (string-contains path ".."))
       (or (not (string-prefix? "/" path))
           (string-prefix? (getcwd) path))))

(define (safe-command-string? cmd)
  "Checks if the command is a single command without shell operators or redirections."
  (let ((forbidden-chars '(#\; #\& #\| #\` #\$ #\newline #\> #\<)))
    (not (any (lambda (c) (string-index cmd c)) forbidden-chars))))

(define (is-command-safe? cmd)
  "Determines if a command is safe to run without user permission."
  (and (safe-command-string? cmd)
       (let* ((trimmed (string-trim-both cmd))
              (parts (string-split trimmed #\space))
              (first-word (if (null? parts) "" (car parts))))
         (cond
          ((member first-word '("grep" "find" "sed" "awk" "info")) #t)
          ((string=? first-word "git")
           (let ((subcommand (if (and (pair? (cdr parts)) (not (string-null? (cadr parts)))) (cadr parts) "")))
             (member subcommand '("status" "diff" "log" "ls-files"))))
          (else #f)))))

;; Whitelist of allowed primitives from (guile)
(define SAFE-GUILE-EXPORTS
  '(
    ;; Arithmetic
    + - * / = > < >= <= quotient remainder modulo
    positive? negative? zero? odd? even? abs max min

    ;; Booleans
    not and or boolean?

    ;; Lists
    list cons car cdr pair? null? list? length append reverse
    list-ref member memq memv assoc assq assv
    map for-each filter

    ;; Strings
    string? string-length string-append substring string->number number->string
    string=? string<? string>? string-suffix? string-prefix? string-contains

    ;; Symbols
    symbol? symbol->string string->symbol

    ;; Vectors
    vector? vector-length vector-ref vector-set! make-vector vector

    ;; Control Flow
    if cond else => case begin let let* letrec lambda define set!
    do while when unless
    quote quasiquote unquote unquote-splicing

    ;; Basic I/O (Stdout only)
    display newline format write read

    ;; Exceptions (Basic)
    catch throw error

    ;; Ports (String only)
    open-input-string open-output-string get-output-string
    call-with-input-string call-with-output-string
    ))

(define (make-safe-module-interface)
  "Creates a safe module interface containing only whitelisted (guile) exports."
  (let ((safe-m (make-module)))
    (for-each (lambda (sym)
                (let ((var (module-variable (resolve-module '(guile)) sym)))
                  (if var
                      (module-add! safe-m sym var)
                      (display (format #f "Warning: Symbol ~a not found in (guile).\n" sym) (current-error-port)))))
              SAFE-GUILE-EXPORTS)
    safe-m))

(define (make-safe-sandbox-module capabilities)
  "Creates a fresh safe module utilizing the safe interface and injecting capabilities."
  (let ((m (make-module))
        (safe-interface (make-safe-module-interface)))
    (module-use! m safe-interface)

    ;; Pre-load ice-9 match and regex which are standard in GAIA
    (module-use! m (resolve-interface '(ice-9 match)))
    (module-use! m (resolve-interface '(ice-9 regex)))

    ;; Pre-load srfi-1 (List library) which includes fold, append-map, any, every, etc.
    (module-use! m (resolve-interface '(srfi srfi-1)))

    ;; Inject capabilities as procedures
    (for-each (lambda (cap-pair)
                (module-define! m (car cap-pair) (cdr cap-pair)))
              capabilities)
    m))

;; Parenthesis Auto-Healer
(define (analyze-parentheses code-string)
  "Counts missing closing parentheses in a code string."
  (let loop ((chars (string->list code-string))
             (in-string? #f)
             (in-comment? #f)
             (escape? #f)
             (open-parens 0)
             (close-parens 0))
    (if (null? chars)
        (cond
         ((> open-parens close-parens)
          (cons (- open-parens close-parens)
                (format #f "Syntax Error Hint: You have ~a opening '(' but only ~a closing ')'. You are missing ~a closing parentheses!"
                        open-parens close-parens (- open-parens close-parens))))
         ((< open-parens close-parens)
          (cons 0
                (format #f "Syntax Error Hint: You have ~a opening '(' and ~a closing ')'. You have ~a extra closing parentheses!"
                        open-parens close-parens (- close-parens open-parens))))
         (else (cons 0 #f)))
        (let ((c (car chars))
              (rest (cdr chars)))
          (cond
           (escape? (loop rest in-string? in-comment? #f open-parens close-parens))
           (in-comment?
            (if (char=? c #\newline)
                (loop rest in-string? #f #f open-parens close-parens)
                (loop rest in-string? #t #f open-parens close-parens)))
           (in-string?
            (cond
             ((char=? c #\\) (loop rest in-string? in-comment? #t open-parens close-parens))
             ((char=? c #\") (loop rest #f in-comment? #f open-parens close-parens))
             (else (loop rest in-string? in-comment? #f open-parens close-parens))))
           (else
            (cond
             ((char=? c #\() (loop rest in-string? in-comment? #f (+ open-parens 1) close-parens))
             ((char=? c #\)) (loop rest in-string? in-comment? #f open-parens (+ close-parens 1)))
             ((char=? c #\;) (loop rest in-string? #t #f open-parens close-parens))
             ((char=? c #\") (loop rest #t in-comment? #f open-parens close-parens))
             (else (loop rest in-string? in-comment? #f open-parens close-parens)))))))))

(define (auto-heal-parentheses code-string)
  (let* ((res (analyze-parentheses code-string))
         (missing (car res)))
    (if (> missing 0)
        (string-append code-string (make-string missing #\)))
        code-string)))

(define (auto-heal-escape-sequences code-string)
  "Scans the code-string for invalid escape sequences inside string literals and double-escapes them."
  (let loop ((chars (string->list code-string))
             (in-string? #f)
             (in-comment? #f)
             (escape? #f)
             (result '()))
    (if (null? chars)
        (let ((final-res (if escape? (cons #\\ result) result)))
          (list->string (reverse final-res)))
        (let ((c (car chars))
              (rest (cdr chars)))
          (cond
           (in-comment?
            (if (char=? c #\newline)
                (loop rest in-string? #f #f (cons c result))
                (loop rest in-string? #t #f (cons c result))))
           (in-string?
            (if escape?
                (let ((valid-escapes '(#\n #\t #\r #\" #\\ #\0 #\a #\b #\f #\v #\x #\u #\U #\newline)))
                  (if (memv c valid-escapes)
                      (loop rest #t #f #f (cons c (cons #\\ result)))
                      (loop rest #t #f #f (cons c (cons #\\ (cons #\\ result))))))
                (cond
                 ((char=? c #\\) (loop rest #t #f #t result))
                 ((char=? c #\") (loop rest #f #f #f (cons c result)))
                 (else (loop rest #t #f #f (cons c result))))))
           (else
            (cond
             ((char=? c #\;) (loop rest #f #t #f (cons c result)))
             ((char=? c #\") (loop rest #t #f #f (cons c result)))
             (else (loop rest #f #f #f (cons c result))))))))))

;; Python process management
(define (make-python-process)
  (let ((open-process (module-ref (resolve-module '(ice-9 popen)) 'open-process)))
    (catch #t
      (lambda ()
        (call-with-values
            (lambda ()
              (open-process "r+" "sh" "-c" "exec guix shell python -- python3 -u -i -q 2>/dev/null"))
          (lambda (r w pid) (list pid w r))))
      (lambda _
        (call-with-values
            (lambda ()
              (open-process "r+" "sh" "-c" "exec python3 -u -i -q 2>/dev/null"))
          (lambda (r w pid) (list pid w r)))))))

(define (run-python-code py-proc code)
  (match py-proc
    ((pid stdin stdout)
     (let ((tmp-file (format #f "/tmp/gaia_python_~a.py" pid)))
       (catch #t
         (lambda ()
           (call-with-output-file tmp-file
             (lambda (port)
               (display code port))))
         (lambda (key . args)
           (error "Failed to write python code to temporary file" tmp-file)))
       (display (format #f "exec(\"try:\\n    exec(open('~a').read())\\nexcept Exception:\\n    import traceback, sys; traceback.print_exc(file=sys.stdout)\\n\")\n" tmp-file) stdin)
       (display "print('__GAIA_PYTHON_DONE__')\n" stdin)
       (force-output stdin)
       (let loop ((output-lines '()))
         (let ((line (read-line stdout)))
           (cond
            ((eof-object? line)
             (catch #t (lambda () (delete-file tmp-file)) (lambda _ #f))
             (string-join (reverse output-lines) "\n"))
            ((string-prefix? "__GAIA_PYTHON_DONE__" line)
             (catch #t (lambda () (delete-file tmp-file)) (lambda _ #f))
             (string-join (reverse output-lines) "\n"))
            (else
             (loop (cons line output-lines))))))))))

;; Sandbox Record holding state with persistent module
(define-record-type <sandbox>
  (%make-sandbox module initial-symbols python-process event-handler permission-handler)
  sandbox?
  (module sandbox-module set-sandbox-module!)
  (initial-symbols sandbox-initial-symbols)
  (python-process sandbox-python-process set-sandbox-python-process!)
  (event-handler sandbox-event-handler)
  (permission-handler sandbox-permission-handler))

;; Module backup and restore
(define (backup-module m initial-symbols)
  (let ((current-symbols (module-map (lambda (sym var) sym) m)))
    (filter-map (lambda (sym)
                  (if (memq sym initial-symbols)
                      #f
                      (let ((var (module-variable m sym)))
                        (and var (cons sym (variable-ref var))))))
                current-symbols)))

(define (restore-module! m initial-symbols backup)
  (let ((current-symbols (module-map (lambda (sym var) sym) m))
        (backup-syms (map car backup)))
    ;; Remove symbols that were defined but are not in the backup or initial-symbols
    (for-each (lambda (sym)
                (unless (or (memq sym initial-symbols)
                            (memq sym backup-syms))
                  (module-remove! m sym)))
              current-symbols)
    ;; Restore old values from the backup
    (for-each (lambda (pair)
                (module-define! m (car pair) (cdr pair)))
              backup)))

(define (clone-module original-module initial-symbols)
  (let* ((new-m (make-module))
         (current-symbols (module-map (lambda (sym var) sym) original-module)))
    ;; Copy imports from original module
    (for-each (lambda (use)
                (module-use! new-m use))
              (module-uses original-module))
    ;; Copy all local variables
    (for-each (lambda (sym)
                (let ((var (module-variable original-module sym)))
                  (when (and var (not (memq sym initial-symbols)))
                    (module-define! new-m sym (variable-ref var)))))
              current-symbols)
    new-m))

(define (make-sandbox session-id event-handler permission-handler)
  "Creates a secure sandbox environment backing variables natively in a persistent module."
  (let* ((caps '())
         (m (make-safe-sandbox-module caps))
         (initial-symbols (module-map (lambda (sym var) sym) m)))
    (%make-sandbox m initial-symbols #f event-handler permission-handler)))

(define (fork-sandbox original-sandbox)
  "Forks/clones the sandbox state functionally using module cloning."
  (let* ((m-clone (clone-module (sandbox-module original-sandbox)
                                (sandbox-initial-symbols original-sandbox)))
         (py (sandbox-python-process original-sandbox))
         (new-py (if py (make-python-process) #f)))
    (%make-sandbox m-clone
                   (sandbox-initial-symbols original-sandbox)
                   new-py
                   (sandbox-event-handler original-sandbox)
                   (sandbox-permission-handler original-sandbox))))

(define (run-python-in-sandbox sandbox code)
  (let ((py (sandbox-python-process sandbox)))
    (if (not py)
        (let ((new-py (make-python-process)))
          (set-sandbox-python-process! sandbox new-py)
          (run-python-code new-py code))
        (run-python-code py code))))

(define (sandbox-definitions sandbox)
  "Returns an alist of (symbol . value) for all user-defined bindings in the sandbox module."
  (let* ((m (sandbox-module sandbox))
         (initial-symbols (sandbox-initial-symbols sandbox))
         (all-bindings (backup-module m initial-symbols))
         (capability-names '(read-file write-file delete-file list-files run-command
                             system system* run-in-sandbox run-python search-file
                             search-guile-manual run-sed run-awk file-info
                             guile-syntax-check git-status git-diff git-log
                             git-ls-files guix-search guix-package-info
                             get-system-logs get-recent-logs get-boot-logs
                             list-boots get-kernel-logs fork-sandbox
                             read-files patch-file map-files)))
    (filter (lambda (pair)
              (not (memq (car pair) capability-names)))
            all-bindings)))

(define (parse-wisp-string code-str)
  "Parses a Wisp code string into standard Scheme S-expressions wrapped in a begin form."
  (catch #t
    (lambda ()
      (let* ((wisp-lang (lookup-language 'wisp))
             (r (language-reader wisp-lang)))
        (with-input-from-string code-str
          (lambda ()
            (let loop ((forms '()))
              (let ((form (r (current-input-port) #f)))
                (if (eof-object? form)
                    (list 'ok (cons 'begin (reverse forms)))
                    (loop (cons form forms)))))))))
    (lambda (key . args)
      (list 'error 'syntax (format #f "Wisp Parser Error (~a): ~a" key args)))))

;; Sandbox execution engine
(define* (sandbox-eval sandbox code-string #:key (permission-handler #f) (injected-bindings '()))
  "Evaluates Guile Scheme code securely in the persistent module, with rollback on error."
  (let* ((is-wisp? (string-prefix? ";; wisp" (string-trim-both code-string)))
         (parsed (if is-wisp?
                     (parse-wisp-string code-string)
                     (let* ((escapes-healed (auto-heal-escape-sequences code-string))
                            (healed (auto-heal-parentheses escapes-healed)))
                       (catch #t
                         (lambda ()
                           (with-input-from-string (string-append "(begin " healed ")")
                             (lambda ()
                               (let ((expr (read)))
                                 (catch #t
                                   (lambda ()
                                     (let ((next (read)))
                                       (if (eof-object? next)
                                           (list 'ok expr)
                                           (error 'syntax-error "Trailing garbage detected"))))
                                   (lambda _
                                     (error 'syntax-error "Extra closing parentheses detected")))))))
                         (lambda (key . args)
                           (let* ((arg-str (format #f "~a" args))
                                  (hint (if (and (eq? key 'read-error)
                                                 (string-contains arg-str "escape sequence"))
                                            "\nLLM Hint: In Guile Scheme string literals, backslashes must only be used for standard escapes (like \\n, \\t, \\\\, \\\"). Do not escape other characters (like \\} or \\$). If you need a literal backslash, use double-backslash \\\\."
                                            "")))
                             (list 'error 'syntax (string-append "Syntax Error (" (symbol->string key) "): " arg-str hint)))))))))
    (if (eq? (car parsed) 'error)
        parsed
        (let* ((m (sandbox-module sandbox))
               (initial-symbols (sandbox-initial-symbols sandbox))
               (perm-handler (or permission-handler (sandbox-permission-handler sandbox)))
               ;; Back up current module bindings
               (backup (backup-module m initial-symbols))
               ;; Define capabilities
               (caps
                (list
                 ;; File System Capability (fs-cap)
                 (cons 'read-file
                       (lambda (path)
                         (if (not (safe-path? path))
                             (error "Access Denied: Path outside workspace" path)
                             (read-file path))))
                 (cons 'write-file
                       (lambda (path content)
                         (if (not (safe-path? path))
                             (error "Access Denied: Path outside workspace" path)
                             (if perm-handler
                                 (if (perm-handler `(write-file ,path ,content))
                                     (write-file path content)
                                     (throw 'user-interrupt))
                                 (error "Permission Denied: No permission handler registered for dangerous operation")))))
                 (cons 'delete-file
                       (lambda (path)
                         (if (not (safe-path? path))
                             (error "Access Denied: Path outside workspace" path)
                             (if perm-handler
                                 (if (perm-handler `(delete-file ,path))
                                     (begin
                                       (delete-file path)
                                       (string-append "Deleted file: " path))
                                     (throw 'user-interrupt))
                                 (error "Permission Denied: No permission handler registered for dangerous operation")))))
                 (cons 'list-files
                       (lambda (path)
                         (if (not (safe-path? path))
                             (error "Access Denied: Path outside workspace" path)
                             (list-files path))))
                 ;; Process Capability (process-cap)
                 (cons 'run-command
                       (lambda (cmd)
                         (let ((is-safe? (is-command-safe? cmd)))
                           (if is-safe?
                               (catch #t
                                 (lambda ()
                                   (let ((res (run-in-sandbox cmd)))
                                     (if (string-contains res "guix shell:")
                                         (error "Guix container failed")
                                         res)))
                                 (lambda _
                                   (let* ((pipe (open-pipe (string-append cmd " 2>&1") OPEN_READ))
                                          (out (read-string pipe)))
                                     (close-pipe pipe)
                                     out)))
                               (if perm-handler
                                   (if (perm-handler `(run-command ,cmd))
                                       (catch #t
                                         (lambda ()
                                           (let ((res (run-in-sandbox cmd)))
                                             (if (string-contains res "guix shell:")
                                                 (error "Guix container failed")
                                                 res)))
                                         (lambda _
                                           (let* ((pipe (open-pipe (string-append cmd " 2>&1") OPEN_READ))
                                                  (out (read-string pipe)))
                                             (close-pipe pipe)
                                             out)))
                                       (throw 'user-interrupt))
                                   (error "Permission Denied: No permission handler registered for dangerous operation"))))))
                 (cons 'system
                       (lambda (cmd)
                         (if perm-handler
                             (if (perm-handler `(system ,cmd))
                                 (let* ((pipe (open-pipe (string-append cmd " 2>&1") OPEN_READ))
                                        (out (read-string pipe)))
                                   (close-pipe pipe)
                                   out)
                                 (throw 'user-interrupt))
                             (error "Permission Denied: No permission handler registered for dangerous operation"))))
                 (cons 'system*
                       (lambda args
                         (let ((cmd (string-join (map (lambda (a) (format #f "~a" a)) args) " ")))
                           (if perm-handler
                               (if (perm-handler `(system* ,cmd))
                                   (let* ((pipe (open-pipe (string-append cmd " 2>&1") OPEN_READ))
                                          (out (read-string pipe)))
                                     (close-pipe pipe)
                                     out)
                                   (throw 'user-interrupt))
                               (error "Permission Denied: No permission handler registered for dangerous operation")))))
                 (cons 'run-in-sandbox
                       (lambda (cmd)
                         (if perm-handler
                             (if (perm-handler `(run-in-sandbox ,cmd))
                                 (run-in-sandbox cmd)
                                 (throw 'user-interrupt))
                             (error "Permission Denied: No permission handler registered for dangerous operation"))))
                 ;; Python Polyglot Capability (python-cap)
                 (cons 'run-python
                       (lambda (py-code)
                         (if perm-handler
                             (if (perm-handler `(run-python ,py-code))
                                 (run-python-in-sandbox sandbox py-code)
                                 (throw 'user-interrupt))
                             (error "Permission Denied: No permission handler registered for dangerous operation"))))
                 ;; Search capabilities
                 (cons 'search-file search-file)
                 (cons 'search-guile-manual search-guile-manual)
                 (cons 'run-sed run-sed)
                 (cons 'run-awk run-awk)
                 (cons 'file-info file-info)
                 (cons 'guile-syntax-check guile-syntax-check)
                 ;; Git capabilities
                 (cons 'git-status git-status)
                 (cons 'git-diff git-diff)
                 (cons 'git-log git-log)
                 (cons 'git-ls-files git-ls-files)
                 ;; Guix capabilities
                 (cons 'guix-search guix-search)
                 (cons 'guix-package-info guix-package-info)
                 ;; System Logs capabilities
                 (cons 'get-system-logs get-system-logs)
                 (cons 'get-recent-logs get-recent-logs)
                 (cons 'get-boot-logs get-boot-logs)
                 (cons 'list-boots list-boots)
                 (cons 'get-kernel-logs get-kernel-logs)
                 ;; Fork capability
                 (cons 'fork-sandbox (lambda () (fork-sandbox sandbox)))
                 ;; High-level standard library capabilities
                 (cons 'read-files
                       (lambda (paths)
                         (for-each (lambda (path)
                                     (if (not (safe-path? path))
                                         (error "Access Denied: Path outside workspace" path)))
                                   paths)
                         (read-files paths)))
                 (cons 'patch-file
                       (lambda (path old-string new-string)
                         (if (not (safe-path? path))
                             (error "Access Denied: Path outside workspace" path)
                             (if perm-handler
                                 (if (perm-handler `(write-file ,path ,(string-append "Patch file: replace " old-string " with " new-string)))
                                     (patch-file path old-string new-string)
                                     (throw 'user-interrupt))
                                 (error "Permission Denied: No permission handler registered for dangerous operation")))))
                 (cons 'map-files
                       (lambda (dir pattern proc)
                         (if (not (safe-path? dir))
                             (error "Access Denied: Path outside workspace" dir)
                             (map-files dir pattern proc))))
                 )))

          ;; Inject capabilities and injected bindings into the persistent module
          (for-each (lambda (cap-pair)
                      (module-define! m (car cap-pair) (cdr cap-pair)))
                    (append caps injected-bindings))

          (catch #t
            (lambda ()
              ;; Evaluate expression, capturing stdout
              (let* ((output-port (open-output-string))
                     (res (with-output-to-port output-port
                            (lambda ()
                              (let ((val (eval (cadr parsed) m)))
                                (when (and val (not (unspecified? val)))
                                  (write val))
                                val))))
                     (output (get-output-string output-port))
                     (final-output (if (and (not is-wisp?) (> (car (analyze-parentheses code-string)) 0))
                                       (string-append "[Auto-healed " (number->string (car (analyze-parentheses code-string))) " missing parentheses]\n" output)
                                       output)))
                (close-port output-port)
                (list 'ok final-output)))
            (lambda (key . args)
              ;; Automatic rollback (restore the module state to backup!)
              (restore-module! m initial-symbols backup)
              (cond
               ((eq? key 'user-interrupt)
                (apply throw key args))
               ((eq? key 'syntax-error)
                (match args
                  ((subr msg loc expr . rest)
                   (list 'error 'syntax (format #f "Syntax Error: ~a\nIn expression: ~s" msg expr)))
                  (_
                   (list 'error 'syntax (format #f "Syntax Error: ~a" args)))))
               (else
                (list 'error 'runtime (format #f "Runtime Error: ~a ~a" key args))))))))))
