(use-modules (gaia sandbox)
             (srfi srfi-64)
             (ice-9 match))

(test-begin "gaia-wisp-integration")

(define (make-test-sandbox permission-result)
  (make-sandbox "test-session" 
                (lambda (evt) #t) 
                (lambda (expr) permission-result)))

(test-equal "wisp-simple-parsing"
  '(ok "42")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb ";; wisp\ndefine foo 42\n. foo")))

(test-equal "wisp-function-definition"
  '(ok "6")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb ";; wisp\ndefine : add-one x\n  + x 1\n")
    (sandbox-eval sb ";; wisp\nadd-one 5")))

(test-equal "wisp-multiline-indented"
  '(ok "15")
  (let ((sb (make-test-sandbox #t)))
    (sandbox-eval sb ";; wisp\ndefine : sum-to-n n\n  if : = n 0\n    . 0\n    + n : sum-to-n : - n 1\n")
    (sandbox-eval sb ";; wisp\nsum-to-n 5")))

(test-equal "wisp-syntax-error"
  'error
  (car (let ((sb (make-test-sandbox #t)))
         (sandbox-eval sb ";; wisp\n(define foo 42"))))

(let* ((runner (test-runner-current))
       (fail (if runner (test-runner-fail-count runner) 0)))
  (test-end "gaia-wisp-integration")
  (exit (if (> fail 0) 1 0)))
