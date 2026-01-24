(define-module (gaia curator)
  #:use-module (gaia utils)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (curate-dataset))

(define (read-all-lines port)
  (let loop ((line (read-line port))
             (lines '()))
    (if (eof-object? line)
        (reverse lines)
        (loop (read-line port) (cons line lines)))))

(define (parse-line line)
  (catch #t
    (lambda () (json->scm line))
    (lambda _ #f)))

(define (success? record)
  ;; Heuristic: Check if output contains "Error" or "exception"
  (let ((result (assoc-ref record "result")))
    (and result
         (not (string-contains-ci result "error"))
         (not (string-contains-ci result "exception")))))

(define (format-training-example record)
  (let ((input (assoc-ref record "input"))
        (code (assoc-ref record "code")))
    `(("instruction" . ,input)
      ("output" . ,code))))

(define (curate-dataset input-file output-success output-failure)
  (let* ((lines (call-with-input-file input-file read-all-lines))
         (records (filter-map parse-line lines))
         (successes (filter success? records))
         (failures (remove success? records)))
    
    (call-with-output-file output-success
      (lambda (port)
        (for-each (lambda (rec)
                    (display (scm->json (format-training-example rec)) port)
                    (newline port))
                  successes)))
    
    (display (format #f "Curated: ~a successes, ~a failures.\n"
                     (length successes) (length failures)))))
