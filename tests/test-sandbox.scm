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

(test-assert "ocap-path-restriction-write"
  (let ((sb (make-test-sandbox #f)))
    (catch 'user-interrupt
      (lambda ()
        (sandbox-eval sb "(write-file \"/etc/passwd\" \"malicious\")")
        #f)
      (lambda _ #t))))

(test-assert "ocap-path-restriction-find"
  (let ((sb (make-test-sandbox #f)))
    (catch 'user-interrupt
      (lambda ()
        (sandbox-eval sb "(find-files \"/etc\" \"\\\\.txt$\")")
        #f)
      (lambda _ #t))))

(test-equal "ocap-path-restriction-denied-feedback"
  '(error permission "Reason text")
  (let ((sb (make-sandbox "test-session" 
                          (lambda (evt) #t) 
                          (lambda (expr) '(denied "Reason text")))))
    (sandbox-eval sb "(write-file \"/etc/passwd\" \"malicious\")")))


;; 5b. Test Command Injection Hardening
(test-assert "command-hardening-safe"
  (let ((sb (make-test-sandbox #f))) ;; Handlers denied
    ;; git status has no operator and is safe, should succeed directly
    (let ((res (sandbox-eval sb "(run-command \"git status\")")))
      (not (and (pair? res) (eq? (car res) 'error) (string-contains (caddr res) "user-interrupt"))))))

(test-assert "command-hardening-injection-blocked"
  (let ((sb (make-test-sandbox #f))) ;; Handlers denied
    ;; Shell grammar is not representable by the direct argv capability.
    (let ((result (sandbox-eval sb "(run-command \"grep foo bar; rm -rf /tmp\")")))
      (and (pair? result) (eq? (car result) 'error)
           (string-contains (caddr result) "cannot represent")))))

(test-assert "command policy parses quoted argv and never invokes a shell"
  (let ((captured #f)
        (sb (make-test-sandbox #f)))
    (let ((approved
           (make-sandbox "argv-policy" (lambda _ #t)
                         (lambda (expr) (set! captured expr) #t))))
      (sandbox-eval approved "(run-command \"printf 'a b'\")")
      (and (equal? captured '(run-command ("printf" "a b")))
           (let ((result
                  (sandbox-eval sb
                                "(run-command \"git status $(touch /tmp/nope)\")")))
             (and (pair? result) (eq? (car result) 'error)
                  (string-contains (caddr result) "cannot represent")))))))

(test-assert "raw system shell is unavailable even with HITL approval"
  (let* ((sb (make-test-sandbox #t))
         (result (sandbox-eval sb "(system \"echo unsafe\")")))
    (and (pair? result) (eq? (car result) 'error)
         (string-contains (caddr result) "Raw shell execution is not supported"))))

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
(test-assert "hitl-approved"
  (let* ((sb (make-test-sandbox #t))) ;; HITL Mock: approved (#t)
    ;; Create temp file
    (sandbox-eval sb "(write-file \"test_temp.txt\" \"hello\")")
    ;; Delete temp file (should succeed because HITL is approved)
    (let ((res (sandbox-eval sb "(delete-file \"test_temp.txt\")")))
      (match res
        (('ok msg)
         (or (string=? msg "\"Deleted file: test_temp.txt\"")
             (string-suffix? "test_temp.txt\"" msg)))
        (_ #f)))))

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

;; 12. Test expand-user-path slash separation
(test-equal "expand-user-path-separator"
  (let ((home (or (getenv "HOME") "/")))
    (if (string-suffix? "/" home)
        (string-append home "test-path")
        (string-append home "/test-path")))
  ((@@ (gaia sandbox) expand-user-path) "~/test-path"))

;; 13. Test newly whitelisted primitives (math, comparisons, alists, hash tables, bitwise, strings, helpers)
(test-equal "whitelisted-math"
  '(ok "6")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb "(inexact->exact (sqrt (* (+ 3 3) (+ 3 3))))")))

(test-equal "whitelisted-comparisons"
  '(ok "#t")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb "(equal? '(1 2 (a)) '(1 2 (a)))")))

(test-equal "whitelisted-list-accessors"
  '(ok "3")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb "(caddr '(1 2 3 4))")))

(test-equal "whitelisted-alist-accessors"
  '(ok "val")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb "(assoc-ref '((key . val)) 'key)")))

(test-equal "whitelisted-hash-tables"
  '(ok "hash-val")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb "(let ((h (make-hash-table))) (hash-set! h 'key 'hash-val) (hash-ref h 'key))")))

(test-equal "whitelisted-bitwise-ops"
  '(ok "2")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb "(logand 6 3)")))

(test-equal "whitelisted-string-helpers"
  '(ok "\"a-b-c\"")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb "(string-join '(\"a\" \"b\" \"c\") \"-\")")))

(test-equal "whitelisted-core-helpers"
  '(ok "6")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb "(apply + '(1 2 3))")))

(let* ((runner (test-runner-current))
       (fail (if runner (test-runner-fail-count runner) 0)))
  (test-end "gaia-sandbox-ocap-goblins")
  (exit (if (> fail 0) 1 0)))
