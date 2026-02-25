(define-module (gaia tools)
  #:use-module (ice-9 match)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 ftw)  ;; File tree walk
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-19)
  #:export (list-files
            read-file
	    write-file
            file-info
            search-file
            run-sed
            run-awk
            guile-syntax-check
            git-status
            git-diff
            git-log
            guix-search
            guix-package-info))

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
  (let* ((pipe (apply open-pipe* OPEN_READ cmd args))
         (output (read-string pipe)))
    (close-pipe pipe)
    (or output "")))

(define (search-file pattern path)
  "Greps for pattern in file."
  (run-cmd-with-output "grep" pattern path))

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

;; --- Guix Tools ---

(define (guix-search query)
  "Searches for Guix packages and returns a concise list of names."
  (run-cmd-with-output "sh" "-c" (string-append "guix search " query " | grep '^name:' | head -n 20")))

(define (guix-package-info pkg)
  "Shows Guix package details."
  (run-cmd-with-output "guix" "show" pkg))
