(add-to-load-path (string-append (dirname (current-filename)) "/../scheme"))
(use-modules (gaia sandbox)
             (gaia executor)
             (srfi srfi-64)
             (ice-9 match))

(test-begin "gaia-tools")

;; Helper to run code in sandbox and return result
(define (run-safe-code code)
  (let ((res (guix-investigate (format #f "~s" code))))
    (match res
      (('ok val-str) 
       (with-input-from-string val-str read))
      (('error type msg) (list 'error type msg)))))

;; 1. Test list-files
(test-assert "list-files"
  (let ((res (run-safe-code '(list-files "."))))
    (display (format #f "Result: ~a\n" res))
    (and (list? res) (member "." res))))

;; 2. Test read-file (read THIS file)
;; We know scripts/test-tools.scm exists.
;; Inside container, it might be at /workspace/scripts/test-tools.scm
(test-assert "read-file"
  (let ((res (run-safe-code '(read-file "scripts/test-tools.scm"))))
    (display (format #f "Read-file Result: ~s\n" res))
    (and (string? res) (string-contains res "(test-begin \"gaia-tools\")"))))

;; 3. Test search-file (grep)
(test-assert "search-file"
  (let ((res (run-safe-code '(search-file "test-begin" "scripts/test-tools.scm"))))
    (and (string? res) (string-contains res "(test-begin \"gaia-tools\")"))))

;; 4. Test run-sed
;; Echo "hello" | sed s/hello/world/ -> No, run-sed takes a file.
;; Let's sed this file.
(test-assert "run-sed"
  (let ((res (run-safe-code '(run-sed "s/test-begin/TEST-BEGIN/g" "scripts/test-tools.scm"))))
    (and (string? res) (string-contains res "(TEST-BEGIN \"gaia-tools\")"))))

;; 5. Test file-info (stat)
(test-assert "file-info"
  (let ((res (run-safe-code '(file-info "scripts/test-tools.scm"))))
    (and (string? res) (string-contains res "Size:") (string-contains res "Type: regular"))))

;; 6. Test write-file
(test-assert "write-file"
  (let* ((filename "test-output.txt")
         (content "Hello from GAIA Sandbox!")
         (res-write (run-safe-code `(write-file ,filename ,content)))
         (res-read (run-safe-code `(read-file ,filename))))
    (and (string-contains res-write "Written 24 bytes")
         (string=? res-read content))))

;; 7. Test banned system (ensure tools didn't leak system)
(test-equal "banned-system-still-blocked"
  '(error permission "Security Violation: Usage of banned primitive 'system' is not allowed.")
  (run-safe-code '(system "ls")))

(test-end "gaia-tools")
