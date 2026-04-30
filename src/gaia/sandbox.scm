(define-module (gaia sandbox)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)  ;; List library
  #:export (make-safe-module eval-safe))

;; Whitelist of allowed primitives from (guile)
(define SAFE-GUILLE-EXPORTS
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
    string=? string<? string>?

    ;; Symbols
    symbol? symbol->string string->symbol

    ;; Vectors
    vector? vector-length vector-ref vector-set! make-vector vector

    ;; Control Flow
    if cond case begin let let* letrec lambda define set!
    do while ;; Macros often need syntax-rules which is in (guile)
    quote quasiquote unquote unquote-splicing

    ;; Basic I/O (Stdout only)
    display newline format write read

    ;; Exceptions (Basic)
    catch throw error

    ;; File System Operations (POSIX-like)
    stat lstat
    stat:type stat:size stat:mode stat:mtime stat:atime stat:ctime
    file-exists?
    dirname basename

    ;; Ports (String only - for now)
    open-input-string open-output-string get-output-string
    call-with-input-string call-with-output-string

    ;; Modules
    use-modules
    ))

(define (make-safe-interface)
  "Creates a module interface that only exports SAFE-GUILLE-EXPORTS."
  (let ((m (make-module)))
    (beautify-user-module! m) ;; Populate with default guile bindings first
    ;; Now allow only whitelisted exports from this interface
    ;; Actually, easier: Create a fresh module, and copy bindings from (guile) to it.
    (let ((safe-m (make-module)))
      (for-each (lambda (sym)
                  (let ((var (module-variable (resolve-module '(guile)) sym)))
                    (if var
                        (module-add! safe-m sym var)
                        (display (format #f "Warning: Symbol ~a not found in (guile).\n" sym)))))
                SAFE-GUILLE-EXPORTS)
      safe-m)))

(define (make-safe-module)
  "Creates a fresh module that uses ONLY the safe interface."
  (let ((m (make-module))
        (safe-interface (make-safe-interface)))
    ;; We do NOT want (guile) by default. make-module creates an empty one but usually
    ;; the system adds the-root-module.

    ;; Add our safe interface
    (module-use! m safe-interface)

    ;; Add other safe libraries
    (module-use! m (resolve-interface '(ice-9 match)))
    (module-use! m (resolve-interface '(ice-9 regex)))
    (module-use! m (resolve-interface '(srfi srfi-1)))
    (module-use! m (resolve-interface '(srfi srfi-13)))
    (module-use! m (resolve-interface '(gaia tools)))
    m))

(define (eval-safe code-sexp)
  "Evaluates s-expression in a fresh safe module."
  (let ((m (make-safe-module)))
    (eval code-sexp m)))
