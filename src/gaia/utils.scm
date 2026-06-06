(define-module (gaia utils)
  #:export (json->scm
            scm->json
            read-json-file
            write-json-file
            send-event
            save-session
            load-session))

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

(define (send-event client-socket event)
  "Write an S-expression event to client, flushing immediately."
  (write event client-socket)
  (newline client-socket)
  (force-output client-socket))

(define (save-session session-id history)
  (unless (file-exists? "sessions")
    (mkdir "sessions"))
  (let ((port (open-file (string-append "sessions/" session-id ".json") "w")))
    (display (scm->json (list->vector history)) port)
    (close-port port)))

(define (load-session session-id)
  (let ((path (string-append "sessions/" session-id ".json")))
    (if (file-exists? path)
        (let* ((port (open-file path "r"))
               (data (read-string port)))
          (close-port port)
          (let ((res (json->scm data)))
            (if (vector? res) (vector->list res) res)))
        '())))
