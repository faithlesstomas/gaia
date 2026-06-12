(add-to-load-path (string-append (dirname (current-filename)) "/../src"))
(use-modules (gaia sandbox)
             (gaia executor)
             (gaia tools)  ;; For direct testing
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
  (let ((res (run-safe-code '(read-file "tests/test-tools.scm"))))
    (display (format #f "Read-file Result: ~s\n" res))
    (and (string? res) (string-contains res "(test-begin \"gaia-tools\")"))))

;; 3. Test search-file (grep)
(test-assert "search-file"
  (let ((res (run-safe-code '(search-file "test-begin" "tests/test-tools.scm"))))
    (and (string? res) (string-contains res "(test-begin \"gaia-tools\")"))))

;; 4. Test run-sed
;; Echo "hello" | sed s/hello/world/ -> No, run-sed takes a file.
;; Let's sed this file.
(test-assert "run-sed"
  (let ((res (run-safe-code '(run-sed "s/test-begin/TEST-BEGIN/g" "tests/test-tools.scm"))))
    (and (string? res) (string-contains res "(TEST-BEGIN \"gaia-tools\")"))))

;; 5. Test file-info (stat)
(test-assert "file-info"
  (let ((res (run-safe-code '(file-info "tests/test-tools.scm"))))
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

;; 8. Test guile-syntax-check (Valid)
(test-assert "guile-syntax-check-valid"
  (let ((res (run-safe-code '(guile-syntax-check "(define (foo x) (+ x 1))"))))
    (and (string? res) (string=? res "OK"))))

;; 9. Test guile-syntax-check (Invalid)
(test-assert "guile-syntax-check-invalid"
  (let ((res (run-safe-code '(guile-syntax-check "(define (foo x) (+ x 1)"))))
    (and (string? res) (string-prefix? "Syntax Error:" res))))

;; 10. Test git-status (Basic structure)
(test-assert "git-status"
  (let ((res (run-safe-code '(git-status))))
    (and (string? res) (string-contains res "##")))) ;; git status -s -b prints "## branch"

;; 11. Test git-log (Basic structure)
(test-assert "git-log"
  (let ((res (run-safe-code '(git-log 1))))
    (and (string? res) (> (string-length res) 5)))) ;; Should contain at least commit hash

;; 12. Test guix-search (Basic execution)
;; NOTE: guix search might be slow in container or require specific setup.
;; We just verify it doesn't crash structurally.
(test-assert "guix-search"
  (let ((res (run-safe-code '(guix-search "guile"))))
    (display (format #f "Guix-search Result: ~s\n" res))
    (string? res)))

;; 13. Test search-guile-manual
(test-assert "search-guile-manual"
  (let ((res (run-safe-code '(search-guile-manual "format"))))
    (and (string? res) (> (string-length res) 10))))

;; 14. Test list-boots (Direct)
(test-assert "list-boots-direct"
  (let ((res (list-boots)))
    (and (string? res) (string-contains res "0"))))

;; 15. Test get-recent-logs (Direct)
(test-assert "get-recent-logs-direct"
  (let ((res (get-recent-logs 5)))
    (and (string? res) (> (string-length res) 5))))

;; 16. Error & Safety validation branches
(test-assert "safe-path? validation error"
  (catch #t
    (lambda ()
      (list-files "../")
      #f)
    (lambda (key . args)
      (eq? key 'gdb-error) ;; Or standard scheme error
      #t)))

(test-assert "read-file: file not found error"
  (catch #t
    (lambda ()
      (read-file "non_existent_file_xyz.txt")
      #f)
    (lambda _ #t)))

;; 17. Git diff & ls-files
(test-assert "git-diff direct"
  (let ((res (git-diff)))
    (string? res)))

(test-assert "git-ls-files direct"
  (let ((res (git-ls-files)))
    (and (list? res) (member "Makefile" res))))

;; 18. Guix show / package-info
(test-assert "guix-package-info direct"
  (let ((res (guix-package-info "guile")))
    (string? res)))

;; 19. Additional logs helpers
(test-assert "get-system-logs direct"
  (let ((res (get-system-logs "cron" 5)))
    (string? res)))

(test-assert "get-boot-logs direct"
  (let ((res (get-boot-logs "" 5)))
    (string? res)))

(test-assert "get-kernel-logs direct"
  (let ((res (get-kernel-logs 5)))
    (string? res)))

;; 20. Guix container support predicate check
(test-assert "guix-container-supported? returns boolean"
  (boolean? ((@@ (gaia tools) guix-container-supported?))))

(let* ((runner (test-runner-current))
       (fail (if runner (test-runner-fail-count runner) 0)))
  (test-end "gaia-tools")
  (exit (if (> fail 0) 1 0)))
