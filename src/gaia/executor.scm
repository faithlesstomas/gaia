(define-module (gaia executor)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 format)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-13)  ;; Strings
  #:use-module (gaia rlm-env)
  #:export (guix-investigate rlm-execute))

(define* (rlm-execute env code-string #:key (permission-handler #f))
  "Executes code in the persistent RLM environment (fast, stateful, native).
ENV is an rlm-env record. Returns ('ok result) or ('error type message)."
  (rlm-eval! env code-string #:permission-handler permission-handler))

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
                    (let* ((command (format #f "guix shell --container --share=./=/workspace guile coreutils grep sed gawk bash git guix texinfo gzip -- ~a" bash-cmd))
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
