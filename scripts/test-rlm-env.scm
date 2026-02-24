(add-to-load-path (string-append (dirname (current-filename)) "/../scheme"))

(use-modules (gaia rlm-env)
             (srfi srfi-64))

(test-begin "rlm-env")

;; --- State Persistence ---

(test-group "state-persistence"
  (let ((env (make-rlm-env)))
    ;; Define a variable
    (test-equal "define variable"
      '(ok "")
      (rlm-eval! env "(define x 42)"))

    ;; Read it back in a subsequent eval
    (test-equal "read variable back"
      '(ok "42")
      (rlm-eval! env "(display x)"))

    ;; Define a function and use it
    (test-equal "define and use function"
      '(ok "84")
      (begin
        (rlm-eval! env "(define (double n) (* n 2))")
        (rlm-eval! env "(display (double x))")))

    ;; Mutate state
    (test-equal "mutate state with set!"
      '(ok "100")
      (begin
        (rlm-eval! env "(set! x 100)")
        (rlm-eval! env "(display x)")))))

;; --- Pre-loaded Modules ---

(test-group "pre-loaded-modules"
  (let ((env (make-rlm-env)))
    ;; SRFI-1: filter
    (test-equal "srfi-1 filter available"
      '(ok "(1 3 5)")
      (rlm-eval! env "(display (filter odd? '(1 2 3 4 5)))"))

    ;; SRFI-13: string-suffix?
    (test-equal "srfi-13 string-suffix? available"
      '(ok "#t")
      (rlm-eval! env "(display (string-suffix? \".scm\" \"core.scm\"))"))

    ;; ice-9 regex: string-match
    (test-equal "ice-9 regex string-match available"
      '(ok "hello")
      (rlm-eval! env "(display (match:substring (string-match \"(hello)\" \"say hello world\") 1))"))

    ;; gaia tools: list-files
    (test-assert "gaia tools list-files available"
      (let ((result (rlm-eval! env "(display (list-files \"scheme/gaia\"))")))
        (and (pair? result)
             (eq? (car result) 'ok)
             (string-contains (cadr result) "core.scm"))))))

;; --- Safety Validation ---

(test-group "safety"
  (let ((env (make-rlm-env)))
    ;; Banned primitive: system
    (test-equal "blocks system call"
      'error
      (car (rlm-eval! env "(system \"ls\")")))

    ;; Banned primitive: system*
    (test-equal "blocks system* call"
      'error
      (car (rlm-eval! env "(system* \"ls\")")))

    ;; Banned primitive: delete-file
    (test-equal "blocks delete-file"
      'error
      (car (rlm-eval! env "(delete-file \"important.txt\")")))

    ;; Safe code still works
    (test-equal "safe code works"
      '(ok "hello")
      (rlm-eval! env "(display \"hello\")"))))

;; --- Syntax Error Handling ---

(test-group "syntax-errors"
  (let ((env (make-rlm-env)))
    ;; Unmatched parens
    (test-equal "catches syntax error"
      'error
      (car (rlm-eval! env "(define x")))

    ;; Valid code still works after error
    (test-equal "env survives syntax error"
      '(ok "42")
      (rlm-eval! env "(display 42)"))))

;; --- Injection ---

(test-group "injection"
  (let ((env (make-rlm-env)))
    ;; Inject a variable
    (rlm-inject! env 'my-context "Hello from context")
    (test-equal "injected variable accessible"
      '(ok "Hello from context")
      (rlm-eval! env "(display my-context)"))

    ;; Inject a function
    (rlm-inject! env 'my-func (lambda (x) (string-append "Got: " x)))
    (test-equal "injected function callable"
      '(ok "Got: test")
      (rlm-eval! env "(display (my-func \"test\"))"))))

;; --- History ---

(test-group "history"
  (let ((env (make-rlm-env)))
    (rlm-eval! env "(display 1)")
    (rlm-eval! env "(display 2)")
    (test-equal "history has 2 entries"
      2
      (length (rlm-env-history env)))))

(test-end "rlm-env")
