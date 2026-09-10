(define-module (gaia utils)
  #:export (json->scm
            scm->json
            read-json-file
            write-json-file
            send-event
            valid-session-id?
            save-session
            load-session))

(use-modules (json)
             (ice-9 match)
             (ice-9 rdelim)
             (ice-9 popen)
             (srfi srfi-1))

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
  (when (and client-socket (not (port-closed? client-socket)))
    (catch #t
      (lambda ()
        (write event client-socket)
        (newline client-socket)
        (force-output client-socket))
      (lambda _ #f))))

(define (valid-session-id? session-id)
  "Accept only bounded identifiers that cannot escape the session directory."
  (and (string? session-id)
       (> (string-length session-id) 0)
       (<= (string-length session-id) 128)
       (every (lambda (character)
                (or (char-alphabetic? character)
                    (char-numeric? character)
                    (memv character '(#\- #\_ #\.))))
              (string->list session-id))))

(define (save-session session-id history)
  (unless (valid-session-id? session-id)
    (error "Invalid session identifier" session-id))
  (unless (file-exists? "sessions")
    (mkdir "sessions"))
  (let ((port (open-file (string-append "sessions/" session-id ".json") "w")))
    (display (scm->json (list->vector history)) port)
    (close-port port)))

(define (load-session session-id)
  (unless (valid-session-id? session-id)
    (error "Invalid session identifier" session-id))
  (let ((path (string-append "sessions/" session-id ".json")))
    (if (file-exists? path)
        (let* ((port (open-file path "r"))
               (data (read-string port)))
          (close-port port)
          (let ((res (json->scm data)))
            (if (vector? res) (vector->list res) res)))
        '())))
