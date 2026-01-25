
(add-to-load-path (string-append (dirname (current-filename)) "/../scheme"))

(use-modules (gaia executor)
             (ice-9 match))

(display "[TEST] Starting Static Safety Validator Test...\n")

(define (test-case name code should-pass?)
  (display (format #f "\n[CASE] ~a\nCode: ~a\n" name code))
  (let ((result (guix-investigate code)))
    (if (string-contains result "Security Violation")
        (if should-pass?
            (display (format #f "FAIL: Expected success, got violation: ~a\n" result))
            (display (format #f "PASS: Blocked as expected: ~a\n" result)))
        (if should-pass?
            (display (format #f "PASS: Executed successfully: ~a\n" result))
            (display (format #f "FAIL: Expected blocking, got execution: ~a\n" result))))))

;; 1. Safe Code
(test-case "Safe Display" 
           "(display \"Hello World\")" 
           #t)

;; 2. Direct Unsafe Code
(test-case "Unsafe System Call" 
           "(system* \"ls\")" 
           #f)

;; 3. Nested Unsafe Code
(test-case "Nested Unsafe Call" 
           "(begin (display \"Safe\") (system* \"rm -rf /\"))" 
           #f)

;; 4. Tricky Nested Unsafe Code
(test-case "Deeply Nested" 
           "(let ((x 1)) (if #t (delete-file \"important.txt\") (display x)))" 
           #f)

;; 5. Regression: Dotted List (Variadic Args)
(test-case "Dotted List (Safe)" 
           "(define (list-files . dirs) (display dirs))" 
           #t)

(display "\n[TEST] Finished.\n")
