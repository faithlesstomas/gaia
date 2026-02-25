(use-modules (gaia executor))
(use-modules (srfi srfi-64))

(test-begin "error-handling-structured")

;; Test 1: Syntax Error
(test-equal "Syntax Error"
  '(error syntax "Error: Could not parse code (Syntax Error).")
  (guix-investigate "(define x"))

;; Test 2: Safety Violation
(test-equal "Safety Violation"
  '(error permission "Security Violation: Usage of banned primitive 'system' is not allowed.")
  (guix-investigate "(system \"ls\")"))

;; Test 3: Runtime Error
(let ((result (guix-investigate "(/ 1 0)")))
  (test-assert "Runtime Error type detection"
    (and (equal? (car result) 'error)
         (equal? (cadr result) 'runtime)
         (string-contains (caddr result) "Error: Execution failed with exit code"))))

;; Test 4: Success
(test-equal "Success Execution"
  '(ok "42")
  (guix-investigate "(display 42)"))

(test-end "error-handling-structured")

(test-begin "core-error-handling")

(define handle-error (@@ (gaia core) handle-error))

(test-assert "Handle Syntax Error"
  (string-contains (handle-error 'syntax "Bad paren" 0) "Syntax Error"))

(test-assert "Handle Permission Error"
  (string-contains (handle-error 'permission "Don't use system" 0) "Security Violation"))

(test-assert "Handle Runtime Error"
  (string-contains (handle-error 'runtime "Division by zero" 0) "Runtime Error"))

(test-end "core-error-handling")
