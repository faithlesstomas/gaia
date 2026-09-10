(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

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
      (let ((result (rlm-eval! env "(display (list-files \"src/gaia\"))")))
        (and (pair? result)
             (eq? (car result) 'ok)
             (string-contains (cadr result) "core.scm"))))))

;; --- Safety Validation ---

(test-group "safety"
  (let ((env (make-rlm-env)))
    ;; Dangerous primitive without handler: system
    (test-equal "blocks system call"
      'error
      (car (rlm-eval! env "(system \"ls\")")))

    ;; Dangerous primitive without handler: system*
    (test-equal "blocks system* call"
      'error
      (car (rlm-eval! env "(system* \"ls\")")))

    ;; Dangerous primitive without handler: delete-file
    (test-equal "blocks delete-file"
      'error
      (car (rlm-eval! env "(delete-file \"important.txt\")")))

    ;; Dangerous primitive without handler: run-in-sandbox
    (test-equal "blocks run-in-sandbox"
      'error
      (car (rlm-eval! env "(run-in-sandbox \"rm -rf /\")")))

    ;; Dangerous primitive without handler: write-file
    (test-equal "blocks write-file"
      'error
      (car (rlm-eval! env "(write-file \"foo.txt\" \"bar\")")))

    ;; Safe code still works
    (test-equal "safe code works"
      '(ok "hello")
      (rlm-eval! env "(display \"hello\")"))))

;; --- HITL Permission Handler ---

(test-group "hitl-permission"
  ;; Handler that always approves → code is NOT blocked by permission system
  ;; (it may still fail at runtime, but the safety gate is bypassed)
  (let ((env (make-rlm-env)))
    (let ((result (rlm-eval! env "(delete-file \"/nonexistent\")"
                             #:permission-handler (lambda (expr) #t))))
      (test-assert "handler-approve bypasses safety gate"
        ;; Result should be a runtime error (file not found), NOT a permission error
        (not (and (pair? result) (eq? (car result) 'error)
                  (pair? (cdr result)) (eq? (cadr result) 'permission))))))

  ;; Raw shell execution is unavailable even when a handler exists.
  (let ((env (make-rlm-env)))
    (test-assert "raw shell is rejected before HITL"
      (let ((result (rlm-eval! env "(system \"ls\")"
                               #:permission-handler (lambda (expr) #t))))
        (and (pair? result) (eq? (car result) 'error)
             (string-contains (caddr result)
                              "Raw shell execution is not supported")))))

  ;; Safe code with handler → handler is never called
  (let* ((env (make-rlm-env))
         (called? #f))
    (test-equal "handler not called for safe code"
      '(ok "42")
      (rlm-eval! env "(display 42)"
                 #:permission-handler (lambda (expr) (set! called? #t) #t)))
    (test-assert "handler was indeed not called"
      (not called?)))

  ;; Handler receives the full dangerous expression
  (let* ((env (make-rlm-env))
         (captured-expr #f))
    (rlm-eval! env "(run-in-sandbox \"echo hello\")"
               #:permission-handler (lambda (expr)
                                      (set! captured-expr expr)
                                      #t))
    (test-assert "handler receives full expression"
      (and (pair? captured-expr)
           (eq? (car captured-expr) 'run-in-sandbox)
           (equal? (cadr captured-expr) '("echo" "hello"))))))

;; --- Syntax Error Handling ---

(test-group "syntax-errors"
  (let ((env (make-rlm-env)))
    ;; Unmatched parens - auto-healing
    (test-equal "heals unmatched closing parentheses"
      '(ok "[System Warning: Auto-healed 1 missing parentheses. Evaluation succeeded. Result follows:]\n42")
      (rlm-eval! env "(display 42"))

    ;; Unmatched parens - extra closing parens (cannot heal)
    (test-equal "catches syntax error for extra closing parens"
      'error
      (car (rlm-eval! env "(display 42)))")))

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

(let* ((runner (test-runner-current))
       (fail (if runner (test-runner-fail-count runner) 0)))
  (test-end "rlm-env")
  (exit (if (> fail 0) 1 0)))
