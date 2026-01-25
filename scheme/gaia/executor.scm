(define-module (gaia executor)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 format)
  #:use-module (ice-9 match)
  #:export (guix-investigate))

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

(define (guix-investigate s-expression-code)
  "Executes the given S-expression code inside a guix shell container."
  (let* ((wrapped-str (format #f "(begin ~a)" s-expression-code))
         ;; Parse locally to validate
         (parsed-sexp (catch #t 
                             (lambda () (with-input-from-string wrapped-str read))
                             (lambda _ #f))))
    
    (if (not parsed-sexp)
        "Error: Could not parse code (Syntax Error)."
        (let ((safety-result (validate-safety parsed-sexp)))
          (if (string? safety-result)
              safety-result ;; Return security error
              ;; Proceed with execution if safe
              (let* ((escaped-code (string-join (string-split wrapped-str #\') "'\\''"))
                     (command (format #f "guix shell --container --share=./=/workspace guile coreutils grep -- guile -c '(chdir \"/workspace\") ~a' 2>&1" escaped-code))
                     (port (open-input-pipe command))
                     (result (read-string port))
                     (exit-val (status:exit-val (close-pipe port))))
                (if (eq? exit-val 0)
                    result
                    (string-append "Error: Execution failed with exit code " (number->string exit-val)
                                   "\nOutput:\n" result))))))))
