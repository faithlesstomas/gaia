(define-module (gaia executor)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 format)
  #:use-module (ice-9 match)
  #:use-module (gaia rlm-env)
  #:export (guix-investigate rlm-execute))

(define (rlm-execute env code-string)
  "Executes code in the persistent RLM environment (fast, stateful, native).
ENV is an rlm-env record. Returns ('ok result) or ('error type message)."
  (rlm-eval! env code-string))

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
  "Executes the given S-expression code inside a guix shell container. Returns (ok result) or (error type message)."
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
              (let* ((escaped-code (string-join (string-split wrapped-str #\') "'\\''"))
                     ;; We wrap the code to run inside our sandbox module
                     ;; We assume /workspace maps to project root, so 'scheme' dir is at /workspace/scheme
                     (container-command 
                      (format #f 
                             "(begin (add-to-load-path \"/workspace/scheme\") (use-modules (gaia sandbox)) (let ((res (eval-safe '~a))) (if (not (unspecified? res)) (write res))))"
                              escaped-code))
                     
                     ;; Helper to shell-quote a string (wrap in single quotes, escape inner single quotes)
                     (shell-quote (lambda (s) (string-append "'" (string-join (string-split s #\') "'\\''") "'")))
                     
                     ;; Level 1: Guile command runs code, redirects stderr to stdout
                     (guile-cmd-inner (format #f "guile --no-auto-compile -c ~a 2>&1" (shell-quote container-command)))
                     
                     ;; Level 2: Bash command runs guile command
                     ;; We explicitly use bash to handle the redirection
                     (bash-cmd (format #f "bash -c ~a" (shell-quote guile-cmd-inner)))

                     ;; Level 3: Guix Shell executes bash
                     (command (format #f "guix shell --container --share=./=/workspace guile coreutils grep sed gawk bash git guix texinfo gzip -- ~a" bash-cmd))
                     (port (open-input-pipe command))
                     (result (read-string port))
                     (exit-val (status:exit-val (close-pipe port))))
                (if (eq? exit-val 0)
                    (list 'ok result)
                    (list 'error 'runtime (string-append "Error: Execution failed with exit code " (number->string exit-val)
                                                         "\nOutput:\n" result)))))))))
