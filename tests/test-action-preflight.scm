(define-module (tests test-action-preflight)
  #:use-module (srfi srfi-64)
  #:use-module (gaia action-preflight))

(test-begin "gaia-action-preflight")

(test-assert "complete Scheme Action passes without evaluation"
  (let ((result (preflight-action "(define untouched-preflight-value 42)\n(+ 20 22)")))
    (and (action-preflight-valid? result)
         (= (length (action-preflight-forms result)) 2)
         (not (defined? 'untouched-preflight-value)))))

(test-assert "reader syntax failure is classified before execution"
  (let ((result (preflight-action "(+ 1 2")))
    (and (not (action-preflight-valid? result))
         (eq? (action-preflight-error-class result) 'READ_SYNTAX)
         (string=? (action-preflight-failing-form result) "(+ 1 2"))))

(test-assert "malformed special form is rejected by macro expansion"
  (let ((result (preflight-action "(let ((x 1) (if #t x 0)) x)")))
    (and (not (action-preflight-valid? result))
         (eq? (action-preflight-error-class result) 'MACRO_SYNTAX)
         (string=? (action-preflight-failing-form result)
                   "(let ((x 1) (if #t x 0)) x)"))))

(test-assert "empty Action fails as incomplete"
  (let ((result (preflight-action "  \n")))
    (and (not (action-preflight-valid? result))
         (eq? (action-preflight-error-class result) 'INCOMPLETE_ACTION))))

(test-end "gaia-action-preflight")
