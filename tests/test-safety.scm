(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (gaia executor)
             (srfi srfi-64)
             (ice-9 match))

(test-begin "gaia-safety")

(define (test-safety-case name code should-pass?)
  (test-assert name
    (let ((result (guix-investigate code)))
      (match result
        (('error 'permission reason)
         (and (not should-pass?)
              (if (string-contains reason "Security Violation") #t #f)))
        (('ok val)
         should-pass?)
        (_ #f)))))

;; 1. Safe Code
(test-safety-case "Safe Display" 
                  "(display \"Hello World\")" 
                  #t)

;; 2. Direct Unsafe Code
(test-safety-case "Unsafe System Call" 
                  "(system* \"ls\")" 
                  #f)

;; 3. Nested Unsafe Code
(test-safety-case "Nested Unsafe Call" 
                  "(begin (display \"Safe\") (system* \"rm -rf /\"))" 
                  #f)

;; 4. Deeply Nested
(test-safety-case "Deeply Nested" 
                  "(let ((x 1)) (if #t (delete-file \"important.txt\") (display x)))" 
                  #f)

;; 5. Regression: Dotted List (Variadic Args)
(test-safety-case "Dotted List (Safe)" 
                  "(define (list-files . dirs) (display dirs))" 
                  #t)

(let* ((runner (test-runner-current))
       (fail (if runner (test-runner-fail-count runner) 0)))
  (test-end "gaia-safety")
  (exit (if (> fail 0) 1 0)))
