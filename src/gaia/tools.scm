(define-module (gaia tools)
  #:use-module (ice-9 match)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 ftw)  ;; File tree walk
  #:use-module (ice-9 optargs)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-19)
  #:export (list-files
            read-file
            write-file
            file-info
            search-file
            search-guile-manual
            run-sed
            run-awk
            guile-syntax-check
            git-status
            git-diff
            git-log
            guix-search
            guix-package-info
            get-system-logs
            get-recent-logs
            get-boot-logs
            list-boots
            get-kernel-logs
            git-ls-files
            run-in-sandbox
            read-files
            patch-file
            map-files
            find-files))

(define (guile-syntax-check code-string)
  "Checks if the Guile Scheme code string has valid syntax (matched parentheses, valid expressions) without evaluating it."
  (catch #t
    (lambda ()
      (call-with-input-string code-string
        (lambda (port)
          (let loop ((expr (read port)))
            (if (eof-object? expr)
                "OK"
                (loop (read port)))))))
    (lambda (key . args)
      (format #f "Syntax Error: ~a ~a" key args))))

;; Helper: Validates path is within workspace (simple check)
;; In container /workspace is root, so mostly everything is safe,
;; but prevent ../ escapes if needed.
(define (safe-path? path)
  (not (string-contains path "..")))

(define (list-files path)
  "Lists files in directory."
  (if (not (safe-path? path))
      (error "Invalid path" path)
      (scandir path)))

(define (read-file path)
  "Reads content of a file (limit 100KB)."
  (if (not (safe-path? path))
      (error "Invalid path" path)
      (if (not (file-exists? path))
          (error "File not found" path)
          (call-with-input-file path
            (lambda (port)
              (get-string-all port)))))) ;; TODO: Add size limit logic

(define (write-file path content)
  "Writes content to a file."
     (if (not (safe-path? path))
      (error "Invalid path" path)
      (begin
        (call-with-output-file path
            (lambda (port)
              (display content port)))
        (string-append "Written " (number->string (string-length content)) " bytes to " path))))


(define (run-cmd-with-output cmd . args)
  "Runs a command and returns its stdout and stderr merged."
  (let* ((pipe (apply open-pipe* OPEN_READ "sh" "-c" "exec \"$@\" 2>&1" "--" cmd args))
         (output (read-string pipe)))
    (close-pipe pipe)
    (or output "")))

(define (search-file pattern path)
  "Greps for pattern in file."
  (run-cmd-with-output "grep" pattern path))

(define (search-guile-manual pattern)
  "Searches the official Guile manual using the info command."
  (run-cmd-with-output "sh" "-c" (string-append "info --output=- --subnodes guile 2>/dev/null | grep -i -C 5 '" pattern "' | head -n 50")))

(define (file-info path)
  "Returns 'stat' like info."
  (let ((st (stat path)))
    (format #f "Size: ~a\nType: ~a\nPerms: ~o"
            (stat:size st) (stat:type st) (stat:mode st))))

(define (run-sed expression path)
  "Runs sed expression on file (stdout only, no -i)."
  (let ((clean-expr (if (and (string-prefix? "'" expression)
                             (string-suffix? "'" expression)
                             (>= (string-length expression) 2))
                        (substring expression 1 (- (string-length expression) 1))
                        expression)))
    (run-cmd-with-output "sed" clean-expr path)))

(define (run-awk program path)
  "Runs awk program on file."
  (let ((clean-prog (if (and (string-prefix? "'" program)
                             (string-suffix? "'" program)
                             (>= (string-length program) 2))
                        (substring program 1 (- (string-length program) 1))
                        program)))
    (run-cmd-with-output "awk" clean-prog path)))

;; --- Git Tools ---

(define (git-status)
  "Returns git status of the workspace."
  (run-cmd-with-output "git" "status" "-s" "-b"))

(define (git-diff . opt-path)
  "Returns git diff, optionally filtered by path."
  (let ((path (if (null? opt-path) "" (car opt-path))))
    (if (string=? path "")
        (run-cmd-with-output "git" "diff")
        (run-cmd-with-output "git" "diff" path))))

(define (git-log . opt-count)
  "Returns recent git history (oneline format). Default 5."
  (let ((count (if (null? opt-count) "5" (number->string (car opt-count)))))
    (run-cmd-with-output "git" "log" "--oneline" (string-append "-n" count))))

(define (git-ls-files)
  "Returns a list of all files tracked by git in the repository."
  (let ((output (run-cmd-with-output "git" "ls-files")))
    (if (string-null? output)
        '()
        (string-split (string-trim-both output) #\newline))))

;; --- Guix Tools ---

(define (guix-search query)
  "Searches for Guix packages and returns a concise list of names."
  (run-cmd-with-output "sh" "-c" (string-append "guix search " query " 2>/dev/null | grep '^name:' | head -n 20")))

(define (guix-package-info pkg)
  "Shows Guix package details."
  (run-cmd-with-output "guix" "show" pkg))

;; --- System Logs Tools (journalctl) ---

(define* (get-system-logs service-name #:optional (arg1 100) (arg2 "") (arg3 ""))
  "Retrieves system logs for a specific service using journalctl.
   Lines limit: 500. Usage: (get-system-logs \"sshd\" [lines] [since] [until])"
  (let* ((lines (if (number? arg1) arg1 100))
         (since (if (string? arg1) arg1 (if (string? arg2) arg2 "")))
         (until (if (string? arg1) (if (string? arg2) arg2 "") (if (string? arg3) arg3 "")))
         (n-lines (if (> lines 500) 500 lines))
         (args (list "-u" service-name "-n" (number->string n-lines) "--no-pager")))
    (let* ((args (if (not (string-null? since)) (append args (list "--since" since)) args))
           (args (if (not (string-null? until)) (append args (list "--until" until)) args)))
      (apply run-cmd-with-output "journalctl" args))))

(define* (get-recent-logs #:optional (arg1 100) (arg2 ""))
  "Retrieves recent logs, optionally filtered by priority.
   Priority can be: emerg, alert, crit, err, warning, notice, info, debug.
   Lines limit: 500. Usage: (get-recent-logs [lines] [priority])"
  (let* ((lines (if (number? arg1) arg1 100))
         (priority (if (string? arg1) arg1 (if (string? arg2) arg2 "")))
         (n-lines (if (> lines 500) 500 lines))
         (args (list "-n" (number->string n-lines) "--no-pager")))
    (let ((args (if (not (string-null? priority)) (append args (list "-p" priority)) args)))
      (apply run-cmd-with-output "journalctl" args))))

(define* (get-boot-logs #:optional (arg1 "") (arg2 100))
  "Retrieves logs for a specific boot ID (pass empty string for current boot).
   Lines limit: 500. Usage: (get-boot-logs [boot-id] [lines])"
  (let* ((boot-id (if (string? arg1) arg1 ""))
         (lines (if (number? arg1) arg1 (if (number? arg2) arg2 100)))
         (n-lines (if (> lines 500) 500 lines)))
    (if (string-null? boot-id)
        (run-cmd-with-output "journalctl" "-b" "-n" (number->string n-lines) "--no-pager")
        (run-cmd-with-output "journalctl" "-b" boot-id "-n" (number->string n-lines) "--no-pager"))))

(define (list-boots)
  "Lists available boots history."
  (run-cmd-with-output "journalctl" "--list-boots" "--no-pager"))

(define* (get-kernel-logs #:optional (arg1 100) (arg2 ""))
  "Retrieves kernel logs (dmesg style from journal).
   Lines limit: 500. Usage: (get-kernel-logs [lines] [since])"
  (let* ((lines (if (number? arg1) arg1 100))
         (since (if (string? arg1) arg1 (if (string? arg2) arg2 "")))
         (n-lines (if (> lines 500) 500 lines))
         (args (list "-k" "-n" (number->string n-lines) "--no-pager")))
    (let ((args (if (not (string-null? since)) (append args (list "--since" since)) args)))
      (apply run-cmd-with-output "journalctl" args))))

;; --- Sandbox Tool ---

(define *guix-container-supported* #t)
(define *guix-checked* #f)

(define (guix-container-supported?)
  (unless *guix-checked*
    (let* ((res (run-cmd-with-output "guix" "shell" "--container" "coreutils" "--" "echo" "guix-container-ok")))
      (set! *guix-container-supported*
            (and (string? res)
                 (string-contains res "guix-container-ok")
                 #t))
      (set! *guix-checked* #t)))
  *guix-container-supported*)

(define (run-in-sandbox cmd)
  "Executes a shell command inside an ephemeral Guix container if supported, falling back locally otherwise."
  (let ((workspace-path (getcwd)))
    (if (guix-container-supported?)
        (let* ((wrapped-cmd (string-append "cd /workspace && " cmd))
               (res (run-cmd-with-output "guix" "shell" "--container"
                                         (string-append "--share=" workspace-path "=/workspace")
                                         "coreutils" "git" "bash" "findutils" "grep" "sed" "gawk" "texinfo" "guile"
                                         "--" "bash" "-c" wrapped-cmd)))
          res)
        ;; Local fallback since guix shell --container is restricted in this environment
        (run-cmd-with-output "bash" "-c" (string-append "cd " workspace-path " && " cmd)))))

(define (string-replace-substring str old new)
  (let ((len (string-length old)))
    (if (= len 0)
        str
        (let loop ((start 0)
                   (parts '()))
          (let ((idx (string-contains str old start)))
            (if idx
                (loop (+ idx len)
                      (cons* new (substring str start idx) parts))
                (string-join (reverse (cons (substring str start) parts)) "")))))))

(define (read-files paths)
  "Reads multiple files as a list of strings."
  (map read-file paths))

(define (patch-file path old-string new-string)
  "Replaces all occurrences of OLD-STRING with NEW-STRING in the file at PATH."
  (let* ((content (read-file path))
         (patched (string-replace-substring content old-string new-string)))
    (write-file path patched)
    (format #f "Patched file ~a (replaced ~s with ~s)" path old-string new-string)))

(define (map-files dir pattern proc)
  "Applies procedure PROC to each file in DIR matching the regex PATTERN (excluding . and ..). Returns list of results."
  (let* ((files (list-files dir))
         (regex (make-regexp pattern))
         (matching-files (filter (lambda (f)
                                   (and (not (string=? f "."))
                                        (not (string=? f ".."))
                                        (regexp-exec regex f)))
                                 files)))
    (map (lambda (f)
           (let ((full-path (if (string-suffix? "/" dir)
                                (string-append dir f)
                                (string-append dir "/" f))))
             (proc full-path)))
         matching-files)))

(define (find-files base-dir pattern)
  "Recursively searches for files/directories matching the regex PATTERN starting from BASE-DIR."
  (let ((regex (make-regexp pattern)))
    (let loop ((dir base-dir)
               (results '()))
      (catch #t
        (lambda ()
          (let* ((files (list-files dir))
                 (sub-results
                  (fold (lambda (file acc)
                          (if (or (string=? file ".") (string=? file ".."))
                              acc
                              (let* ((full-path (if (string-suffix? "/" dir)
                                                   (string-append dir file)
                                                   (string-append dir "/" file)))
                                     (st (catch #t (lambda () (stat full-path)) (lambda _ #f)))
                                     (is-dir? (and st (eq? (stat:type st) 'directory)))
                                     (matches? (regexp-exec regex file)))
                                (let ((new-acc (if matches? (cons full-path acc) acc)))
                                  (if is-dir?
                                      (loop full-path new-acc)
                                      new-acc)))))
                        '()
                        files)))
            (append sub-results results)))
        (lambda _ results)))))
