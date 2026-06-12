(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (gaia executor)
             (srfi srfi-64)
             (ice-9 match))

(test-begin "gaia-traceback")

(test-assert "Capture error traceback from sandbox executor"
  (let ((result (guix-investigate "(error \"This is a test error traceback\")")))
    (match result
      (('error _ msg)
       (if (string-contains msg "This is a test error traceback") #t #f))
      (_ #f))))

(let* ((runner (test-runner-current))
       (fail (if runner (test-runner-fail-count runner) 0)))
  (test-end "gaia-traceback")
  (exit (if (> fail 0) 1 0)))
