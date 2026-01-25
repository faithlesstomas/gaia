(define-module (gaia executor)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 format)
  #:export (guix-investigate))

(define (guix-investigate s-expression-code)
  "Executes the given S-expression code inside a guix shell container."
  (let* ((wrapped-code (format #f "(begin ~a)" s-expression-code))
         ;; Escape single quotes for shell safety
         (escaped-code (string-join (string-split wrapped-code #\') "'\\''"))
         (command (format #f "guix shell --container --share=./=/workspace guile coreutils grep -- guile -c '(chdir \"/workspace\") ~a' 2>&1" escaped-code))
         (port (open-input-pipe command))
         (result (read-string port))
         (exit-val (status:exit-val (close-pipe port))))
    (if (eq? exit-val 0)
        result
        (string-append "Error: Execution failed with exit code " (number->string exit-val)
                       "\nOutput:\n" result))))
