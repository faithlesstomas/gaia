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
            run-awk))

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
