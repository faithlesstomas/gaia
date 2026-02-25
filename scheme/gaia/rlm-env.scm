(define-module (gaia rlm-env)
  #:use-module (ice-9 match)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)   ;; Records
  #:export (make-rlm-env
            rlm-eval!
            rlm-inject!
            rlm-env-history
            rlm-env-module))

;;; --- RLM Environment ---
;;;
;;; A persistent, stateful REPL environment for the Recursive Language Model.
;;; Variables defined in step 1 survive to step 10. Functions like `llm-query`
;;; and `context` are injected as first-class bindings.
;;;

;; Record type for the RLM environment
(define-record-type <rlm-env>
  (%make-rlm-env module history)
  rlm-env?
  (module  rlm-env-module)
  (history rlm-env-history set-rlm-env-history!))

(define (make-safe-rlm-module)
  "Creates a fresh Guile module pre-loaded with safe primitives and libraries
needed for RLM reasoning. This is evaluation without guix container — fast
but restricted to safe operations."
  (let ((m (make-module)))
    ;; Start with standard guile bindings
    (beautify-user-module! m)

    ;; Pre-load essential libraries so the model doesn't have to (use-modules ...)
    ;; This prevents the most common failure: 'Unbound variable: string-suffix?' etc.
    (module-use! m (resolve-interface '(srfi srfi-1)))   ;; Lists: filter, fold, etc.
    (module-use! m (resolve-interface '(srfi srfi-13)))  ;; Strings: string-suffix?, string-contains, etc.
    (module-use! m (resolve-interface '(ice-9 regex)))   ;; Regex: string-match, etc.
    (module-use! m (resolve-interface '(ice-9 match)))   ;; Pattern matching
    (module-use! m (resolve-interface '(ice-9 rdelim)))  ;; read-line, read-string
    (module-use! m (resolve-interface '(ice-9 textual-ports))) ;; get-string-all
    (module-use! m (resolve-interface '(ice-9 ftw)))     ;; scandir, file-system-fold
    (module-use! m (resolve-interface '(gaia tools)))    ;; Safe tools: list-files, read-file, etc.

    ;; Remove dangerous bindings from the base module
    ;; We do this AFTER beautify-user-module! to override defaults
    (for-each (lambda (sym)
                (let ((var (module-variable m sym)))
                  (when var
                    (module-remove! m sym))))
              '(system system* delete-file rmdir rename-file chmod
                primitive-load load))

    ;; Inject helper functions that LLMs commonly expect but Guile lacks.
    ;; These bridge the gap between Python-like string ops and Guile's char-based API.

    ;; (string-after str needle) → substring after needle, or #f
    (module-define! m 'string-after
      (lambda (str needle)
        (let ((idx (string-contains str needle)))
          (if idx
              (substring str (+ idx (string-length needle)))
              #f))))

    ;; (string-before str needle) → substring before needle, or #f
    (module-define! m 'string-before
      (lambda (str needle)
        (let ((idx (string-contains str needle)))
          (if idx
              (substring str 0 idx)
              #f))))

    ;; (extract-match str pattern) → first regex match group, or #f
    ;; Resolve regex functions from the module we already loaded
    (let ((rx-match (module-ref (resolve-interface '(ice-9 regex)) 'string-match))
          (rx-count (module-ref (resolve-interface '(ice-9 regex)) 'match:count))
          (rx-substr (module-ref (resolve-interface '(ice-9 regex)) 'match:substring)))
      (module-define! m 'extract-match
        (lambda (str pattern)
          (let ((result (rx-match pattern str)))
            (if result
                (if (> (rx-count result) 1)
                    (rx-substr result 1)   ;; Return first capture group
                    (rx-substr result 0))  ;; Return full match
                #f)))))

    ;; (split-string str delimiter-string) → list of strings
    ;; LLMs expect this but Guile's string-split only takes a char.
    (module-define! m 'split-string
      (lambda (str delim)
        (let ((dlen (string-length delim)))
          (let loop ((s str) (acc '()))
            (let ((idx (string-contains s delim)))
              (if idx
                  (loop (substring s (+ idx dlen))
                        (append acc (list (substring s 0 idx))))
                  (append acc (list s))))))))

    m))

(define (make-rlm-env)
  "Creates a new RLM environment with a pre-loaded persistent module."
  (%make-rlm-env (make-safe-rlm-module) '()))

(define (rlm-inject! env name value)
  "Injects a named binding into the RLM environment.
NAME should be a symbol, VALUE can be any Scheme value (including closures).
Example: (rlm-inject! env 'llm-query my-query-function)"
  (module-define! (rlm-env-module env) name value))

(define MAX-OUTPUT-LENGTH 4096)  ;; Max chars returned to the LLM to prevent context flood

(define (truncate-output str)
  "Truncates output to MAX-OUTPUT-LENGTH characters."
  (if (> (string-length str) MAX-OUTPUT-LENGTH)
      (string-append (substring str 0 MAX-OUTPUT-LENGTH)
                     "\n... [OUTPUT TRUNCATED at "
                     (number->string MAX-OUTPUT-LENGTH)
                     " chars. Total: "
                     (number->string (string-length str))
                     " chars. Use search-file or process the data in smaller chunks.]")
      str))

(define (rlm-eval! env code-string)
  "Evaluates CODE-STRING in the persistent RLM module.
Returns ('ok result-string) on success or ('error type message) on failure.
State is preserved between calls — variables defined in one call are
visible in subsequent calls. Output is truncated to avoid context flooding."
  (let* ((wrapped (string-append "(begin " code-string ")"))
         ;; Parse the code first
         (parsed (catch #t
                   (lambda () (with-input-from-string wrapped read))
                   (lambda (key . args)
                     (cons 'parse-error
                           (format #f "Syntax Error: ~a ~a" key args))))))

    (if (and (pair? parsed) (eq? (car parsed) 'parse-error))
        ;; Parse failure
        (list 'error 'syntax (cdr parsed))

        ;; Safety check: scan for banned primitives
        (let ((safety (validate-rlm-safety parsed)))
          (if (string? safety)
              (list 'error 'permission safety)

              ;; Evaluate in persistent module
              (let ((result
                     (catch #t
                       (lambda ()
                         ;; Capture stdout
                         (let ((output-port (open-output-string)))
                           (with-output-to-port output-port
                             (lambda ()
                               (let ((val (eval parsed (rlm-env-module env))))
                                 ;; If the expression returns a meaningful value, write it too
                                 (when (and val (not (unspecified? val)))
                                   (write val)))))
                           (let ((output (get-output-string output-port)))
                             (close-port output-port)
                             (list 'ok (truncate-output output)))))
                       (lambda (key . args)
                         (list 'error 'runtime
                               (truncate-output
                                 (format #f "Runtime Error: ~a ~a" key args)))))))

                ;; Record history
                (set-rlm-env-history! env
                  (append (rlm-env-history env)
                          (list (cons code-string result))))
                result))))))

(define BANNED-PRIMITIVES
  '(system system* delete-file rmdir rename-file chmod
    primitive-load load))

(define (validate-rlm-safety sexp)
  "Recursively checks S-expression for banned primitives.
Returns #t if safe, or an error string if unsafe."
  (cond
   ((pair? sexp)
    (let ((head (car sexp))
          (tail (cdr sexp)))
      (if (and (symbol? head) (memq head BANNED-PRIMITIVES))
          (format #f "Security Violation: Usage of banned primitive '~a' is not allowed." head)
          (let ((head-res (validate-rlm-safety head)))
            (if (string? head-res)
                head-res
                (validate-rlm-safety tail))))))
   (else #t)))
