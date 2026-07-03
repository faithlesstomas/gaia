(use-modules (gaia sandbox)
             (srfi srfi-64)
             (ice-9 match))

(test-begin "gaia-sandbox-ocap-goblins")

;; 1. Setup Sandbox
(define (make-test-sandbox permission-result)
  (make-sandbox "test-session" 
                (lambda (evt) #t) 
                (lambda (expr) permission-result)))

;; 2. Test Safe Arithmetic and Basic Logic
(test-equal "safe-arithmetic"
  '(ok "42")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb "(+ 40 2)")))

;; 3. Test Definitions and State Persistence
(test-equal "state-persistence"
  '(ok "15")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb "(define x 5)")
    (sandbox-eval sb "(define (add-ten y) (+ y 10))")
    (sandbox-eval sb "(add-ten x)")))

;; 4. Test Transactional Rollback on Errors
(test-equal "transactional-rollback"
  '(error runtime "Runtime Error: unbound-variable (#f Unbound variable: ~S (y) #f)")
  (let ((sb (make-test-sandbox #t)))
    ;; x is defined successfully
    (sandbox-eval sb "(define x 100)")
    ;; y fails to define due to division by zero
    (sandbox-eval sb "(define y (/ 1 0))")
    ;; Verify y is unbound and rolled back, while x remains intact
    (sandbox-eval sb "y")))

(test-equal "transactional-rollback-verify-intact"
  '(ok "100")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb "(define x 100)")
    (sandbox-eval sb "(define y (/ 1 0))")
    (sandbox-eval sb "x")))

;; 5. Test Ocap Path Restriction
(test-equal "ocap-path-restriction-read"
  '(error runtime "Runtime Error: misc-error (#f Access Denied: Path outside workspace ~S (../secret.txt) #f)")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb "(read-file \"../secret.txt\")")))

(test-equal "ocap-path-restriction-write"
  '(error runtime "Runtime Error: misc-error (#f Access Denied: Path outside workspace ~S (/etc/passwd) #f)")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb "(write-file \"/etc/passwd\" \"malicious\")")))

;; 5b. Test Command Injection Hardening
(test-assert "command-hardening-safe"
  (let ((sb (make-test-sandbox #f))) ;; Handlers denied
    ;; git status has no operator and is safe, should succeed directly
    (let ((res (sandbox-eval sb "(run-command \"git status\")")))
      (not (and (pair? res) (eq? (car res) 'error) (string-contains (caddr res) "user-interrupt"))))))

(test-assert "command-hardening-injection-blocked"
  (let ((sb (make-test-sandbox #f))) ;; Handlers denied
    ;; grep with shell operator (semicolon) is unsafe, should throw user-interrupt
    (catch 'user-interrupt
      (lambda ()
        (sandbox-eval sb "(run-command \"grep foo bar; rm -rf /tmp\")")
        #f)
      (lambda _ #t))))

;; 6. Test Sandbox Forking / Cloning
(test-equal "sandbox-fork-isolation"
  (list '(ok "20") '(ok "30"))
  (let* ((sb-parent (make-test-sandbox #t)))
    ;; 1. Define x in parent
    (sandbox-eval sb-parent "(define x 10)")
    
    ;; 2. Fork parent to child
    (let* ((sb-child (fork-sandbox sb-parent)))
      ;; 3. Modify x in parent to 20
      (sandbox-eval sb-parent "(define x 20)")
      ;; 4. Modify x in child to 30
      (sandbox-eval sb-child "(define x 30)")
      
      ;; 5. Verify isolated values
      (list (sandbox-eval sb-parent "x")
            (sandbox-eval sb-child "x")))))

;; 7. Test HITL Authorization Prompt Mocking
(test-equal "hitl-approved"
  "\"Deleted file: test_temp.txt\""
  (let* ((sb (make-test-sandbox #t))) ;; HITL Mock: approved (#t)
    ;; Create temp file
    (sandbox-eval sb "(write-file \"test_temp.txt\" \"hello\")")
    ;; Delete temp file (should succeed because HITL is approved)
    (let ((res (sandbox-eval sb "(delete-file \"test_temp.txt\")")))
      (match res
        (('ok msg) msg)
        (_ res)))))

(test-assert "hitl-denied throws user-interrupt"
  (let* ((sb-deny (make-test-sandbox #f))) ;; HITL Mock: denied (#f)
    ;; Try to delete file (should throw user-interrupt)
    (catch 'user-interrupt
      (lambda ()
        (sandbox-eval sb-deny "(delete-file \"test_temp.txt\")")
        #f)
      (lambda (key . args) #t))))

;; 8. Test Stateful Polyglot Python REPL
(test-equal "stateful-python-repl"
  "\"300\""
  (let ((sb (make-test-sandbox #t)))
    ;; Run python assignment
    (sandbox-eval sb "(run-python \"a = 100 + 200\")")
    ;; Run python query
    (let ((res (sandbox-eval sb "(run-python \"print(a)\")")))
      (match res
        (('ok val) val)
        (_ res)))))

;; 9. Test Stateful Polyglot Python REPL with Multiline Indented Code
(test-equal "stateful-python-repl-multiline"
  "\"45\""
  (let ((sb (make-test-sandbox #t)))
    ;; Run multiline python block with loop
    (sandbox-eval sb "(run-python \"
total = 0
for i in range(10):
    total += i
\")")
    ;; Query result
    (let ((res (sandbox-eval sb "(run-python \"print(total)\")")))
      (match res
        (('ok val) val)
        (_ res)))))

;; 10. Test cond expression with else clause
(test-equal "cond-with-else"
  '(ok "default-value")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb "(cond (#f 'not-this) (else 'default-value))")))

;; 11. Test Auto-healing of invalid escape sequences in string literals
(test-equal "auto-heal-escape-sequences"
  '(ok "\"hello \\\\world\"")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb "(let ((s \"hello \\world\")) s)")))

(let* ((runner (test-runner-current))
       (fail (if runner (test-runner-fail-count runner) 0)))
  (test-end "gaia-sandbox-ocap-goblins")
  (exit (if (> fail 0) 1 0)))
