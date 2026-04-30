(define-module (gaia utils)
  #:export (json->scm scm->json read-json-file write-json-file))

(use-modules (json)
             (ice-9 match)
             (ice-9 rdelim)
             (ice-9 popen))

(define (json->scm str)
  (json-string->scm str))

(define (scm->json obj)
  (scm->json-string obj))

(define (read-json-file path)
  (call-with-input-file path
    (lambda (port)
      (json->scm (read-string port)))))

(define (write-json-file path obj)
  (call-with-output-file path
    (lambda (port)
      (display (scm->json obj) port))))
