(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (system vm coverage)
             (system vm vm)
             (ice-9 match)
             (ice-9 rdelim)
             (srfi srfi-1))

;; Save original exit procedure
(define real-exit exit)

;; Intercept exit to run all tests in a single process
(module-define! (resolve-module '(guile)) 'exit
                (lambda* (#:optional (status 0))
                  (throw 'exit-intercepted status)))

(define run-with-coverage? (not (getenv "GAIA_NO_COVERAGE")))

(define tests-dir (dirname (current-filename)))

(define test-files
  (map (lambda (f) (string-append tests-dir "/" f))
       '("test-units.scm"
         "test-history.scm"
         "test-final-signal.scm"
         "test-error-handling.scm"
         "test-sandbox.scm"
         "test-tools.scm"
         "test-rlm-env.scm"
         "test-sessions.scm"
         "test-meta-commands.scm"
         "test-actors.scm"
         "test-server.scm"
         "test-safety.scm"
         "test-delegation.scm"
         "test-interrupts.scm"
         "test-traceback.scm"
         "test-curator.scm"
         "test-llm-client.scm")))

(define failed-tests '())

(define (run-test-file file)
  (display (format #f "\n========================================\n"))
  (display (format #f "Running: ~a\n" file))
  (display (format #f "========================================\n"))
  (catch 'exit-intercepted
    (lambda ()
      (load file))
    (lambda (key status)
      (if (= status 0)
          (display (format #f "\n[SUCCESS] ~a finished successfully.\n" file))
          (begin
            (set! failed-tests (cons (cons file status) failed-tests))
            (display (format #f "\n[FAILURE] ~a failed with exit status ~a.\n" file status)))))))

(define (filter-lcov input-path output-path)
  "Filters an LCOV file to only retain records matching gaia/ modules, excluding tests and overrides."
  (let ((input-port (open-input-file input-path))
        (output-port (open-output-file output-path))
        (current-record '())
        (keep? #f))
    (let loop ((line (read-line input-port)))
      (cond
       ((eof-object? line)
        (close-port input-port)
        (close-port output-port))
       ((string-prefix? "SF:" line)
        (let* ((path (substring line 3))
               (canon-path (catch #t (lambda () (canonicalize-path path)) (lambda _ path))))
          (set! keep? (and (or (string-contains canon-path "src/gaia/")
                               (string-contains canon-path "/gaia/")
                               (string-prefix? "gaia/" canon-path))
                           (not (string-contains canon-path "/tests/"))
                           (not (string-contains canon-path "/override/"))))
          (set! current-record (cons (string-append "SF:" canon-path) current-record))
          (loop (read-line input-port))))
       ((string=? "end_of_record" line)
        (set! current-record (cons line current-record))
        (when keep?
          (for-each (lambda (l) (display l output-port) (newline output-port))
                    (reverse current-record)))
        (set! current-record '())
        (set! keep? #f)
        (loop (read-line input-port)))
       (else
        (set! current-record (cons line current-record))
        (loop (read-line input-port)))))))

(if run-with-coverage?
    (begin
      (display "[COVERAGE] Starting test suite under VM instrumentation...\n")
      (call-with-values
        (lambda ()
          (with-code-coverage
            (lambda ()
              (for-each run-test-file test-files))))
        (lambda (data result)
          (display "\n========================================\n")
          (display "[COVERAGE] Writing coverage.info (LCOV format)...\n")
          (let ((raw-path "coverage.info.tmp"))
            (let ((port (open-output-file raw-path)))
              (coverage-data->lcov data port)
              (close-port port))
            
            (display "[COVERAGE] Filtering LCOV report to keep only gaia/ modules...\n")
            (filter-lcov raw-path "coverage.info")
            (delete-file raw-path))
          
          (display "[COVERAGE] Analyzing code coverage results...\n")
          (let* ((files (instrumented-source-files data))
                 (_ (begin (display "\nDEBUG: Instrumented files:\n") (for-each (lambda (f) (display f) (newline)) files)))
                 (gaia-files (filter (lambda (f)
                                       (and (or (string-prefix? "gaia/" f)
                                                (string-contains f "/src/gaia/")
                                                (and (string-contains f "/gaia/")
                                                     (not (string-contains f "/tests/"))
                                                     (not (string-contains f "/override/"))))
                                             (not (string-suffix? "run-coverage.scm" f))))
                                     files)))
            (display "\nCovered source files:\n")
            (let ((grand-total-lines 0)
                  (grand-executed-lines 0))
              (for-each (lambda (file)
                          (let* ((line-data (line-execution-counts data file))
                                 (total-lines (length line-data))
                                 (executed-lines (count (lambda (pair) (> (cdr pair) 0)) line-data))
                                 (percent (if (zero? total-lines) 100 (* (/ executed-lines total-lines) 100.0))))
                            (set! grand-total-lines (+ grand-total-lines total-lines))
                            (set! grand-executed-lines (+ grand-executed-lines executed-lines))
                            (display (format #f "  ~a: ~,2f% (~a/~a lines)\n" 
                                             (basename file) percent executed-lines total-lines))))
                        gaia-files)
              (let ((total-percent (if (zero? grand-total-lines) 100 (* (/ grand-executed-lines grand-total-lines) 100.0))))
                (display (format #f "\n  TOTAL: ~,2f% (~a/~a lines)\n"
                                 total-percent grand-executed-lines grand-total-lines)))))
          
          (display "\n========================================\n")
          (if (null? failed-tests)
              (begin
                (display "[COVERAGE] All tests passed!\n")
                (real-exit 0))
              (begin
                (display "[COVERAGE] Some test suites failed:\n")
                (for-each (lambda (fail)
                            (display (format #f "  ✗ ~a (exit status ~a)\n" (car fail) (cdr fail))))
                          failed-tests)
                (real-exit 1))))))
    (begin
      (display "[COVERAGE] Running test suite without VM instrumentation (warm-up)...\n")
      (for-each run-test-file test-files)
      (display "\n========================================\n")
      (if (null? failed-tests)
          (begin
            (display "[COVERAGE] All warm-up tests passed!\n")
            (real-exit 0))
          (begin
            (display "[COVERAGE] Some warm-up test suites failed:\n")
            (for-each (lambda (fail)
                        (display (format #f "  ✗ ~a (exit status ~a)\n" (car fail) (cdr fail))))
                      failed-tests)
            (real-exit 1)))))
