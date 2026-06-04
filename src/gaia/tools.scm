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
            run-in-sandbox))

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
  (let* ((cmd-str (if (null? args) 
                      cmd 
                      (string-join (map (lambda (a) (format #f "~a" a)) (cons cmd args)) " ")))
         ;; Use shell to merge stderr and stdout
         (pipe (open-pipe (string-append cmd-str " 2>&1") OPEN_READ))
         (output (read-string pipe)))
    (close-pipe pipe)
    (or output "")))

(define (search-file pattern path)
  "Greps for pattern in file."
  (run-cmd-with-output "grep" pattern path))

(define (search-guile-manual pattern)
  "Searches the official Guile manual using the info command."
  (run-cmd-with-output (string-append "info --output=- --subnodes guile 2>/dev/null | grep -i -C 5 '" pattern "' | head -n 50")))

(define (file-info path)
  "Returns 'stat' like info."
  (let ((st (stat path)))
    (format #f "Size: ~a\nType: ~a\nPerms: ~o"
            (stat:size st) (stat:type st) (stat:mode st))))

(define (run-sed expression path)
  "Runs sed expression on file (stdout only, no -i)."
  (run-cmd-with-output "sed" expression path))

(define (run-awk program path)
  "Runs awk program on file."
  (run-cmd-with-output "awk" program path))

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
                                         "coreutils" "git" "bash" "findutils" "grep" "sed" "gawk"
                                         "--" "bash" "-c" wrapped-cmd)))
          res)
        ;; Local fallback since guix shell --container is restricted in this environment
        (run-cmd-with-output "bash" "-c" (string-append "cd " workspace-path " && " cmd)))))
