(define-module (test-sessions)
  #:use-module (srfi srfi-64)
  #:use-module (gaia server)
  #:use-module (gaia rlm-env)
  #:use-module (gaia core)
  #:use-module (gaia utils)
  #:use-module (ice-9 match))

(test-begin "gaia-sessions")

;; Helper to normalize alist keys to symbols for comparison
(define (normalize-keys alist)
  (map (lambda (pair)
         (cons (let ((k (car pair)))
                 (if (string? k) (string->symbol k) k))
               (cdr pair)))
       alist))

(define (normalize-history history)
  (let ((l (if (vector? history) (vector->list history) history)))
    (map normalize-keys l)))

;; Cleanup sessions before test
(when (file-exists? "sessions/test-id.json")
  (delete-file "sessions/test-id.json"))

(test-group "Session Persistence"
  (test-assert "save-session creates a file"
    (begin
      (save-session "test-id" '(((role . "user") (content . "hi"))))
      (file-exists? "sessions/test-id.json")))

  (test-assert "load-session restores history correctly"
    (let ((history (normalize-history (load-session "test-id"))))
      ;; Check if it contains the expected alist, ignoring order of pairs
      (let ((first-turn (car history)))
        (and (equal? (format #f "~a" (assoc-ref first-turn 'role)) "user")
             (equal? (assoc-ref first-turn 'content) "hi"))))))

(test-group "History Replay"
  (test-assert "replay-history restores REPL state"
    (let* ((env (make-rlm-env))
           (history '(((role . "assistant") 
                       (content . "I will define a variable. \n```repl\n(define test-var 123)\n```")))))
      (replay-history env history)
      ;; Check if test-var is defined in the environment
      (let ((res (rlm-eval! env "test-var")))
        ;; rlm-eval! returns ('ok "value")
        (match res
          (('ok "123") #t)
          (_ (begin (display (format #f "[DEBUG] Unexpected eval result: ~a\n" res)) #f)))))))

(test-end "gaia-sessions")

;; Cleanup
(when (file-exists? "sessions/test-id.json")
  (delete-file "sessions/test-id.json"))
