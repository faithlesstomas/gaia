(define-module (gaia rlm-env)
  #:use-module (ice-9 match)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)   ;; Records
  #:use-module (gaia sandbox)
  #:export (make-rlm-env
            rlm-eval!
            rlm-inject!
            rlm-env-history
            rlm-env-module
            rlm-env-user-bindings
            analyze-parentheses
            rlm-env?
            %make-rlm-env
            rlm-env-sandbox
            rlm-env-injected-bindings))

;; Record type for the RLM environment wrapping sandbox
(define-record-type <rlm-env>
  (%make-rlm-env sandbox history injected-bindings)
  rlm-env?
  (sandbox rlm-env-sandbox)
  (history rlm-env-history set-rlm-env-history!)
  (injected-bindings rlm-env-injected-bindings set-rlm-env-injected-bindings!))

(define* (make-rlm-env #:optional (session-id "default") (event-handler #f) (permission-handler #f))
  "Creates a new RLM environment backed by our capability-based Goblins-style sandbox."
  (let ((sandbox (make-sandbox session-id event-handler permission-handler)))
    (%make-rlm-env sandbox '() '())))

(define (rlm-inject! env name value)
  "Injects a named binding into the RLM environment."
  (let ((current (rlm-env-injected-bindings env)))
    (set-rlm-env-injected-bindings! env (cons (cons name value) current))))

(define* (rlm-eval! env code-string #:key (permission-handler #f))
  "Evaluates CODE-STRING in the sandbox. Preserves state and handles rollbacks."
  (let* ((sandbox (rlm-env-sandbox env))
         (injected (rlm-env-injected-bindings env))
         (res (sandbox-eval sandbox code-string
                            #:permission-handler permission-handler
                            #:injected-bindings injected)))
    ;; Record history
    (set-rlm-env-history! env
      (append (rlm-env-history env)
              (list (cons code-string res))))
    res))

(define (rlm-env-module env)
  "Dummy accessor for backward compatibility."
  #f)

(define (rlm-env-user-bindings env)
  "Returns an alist of (symbol . value-string) for variables defined by the user/LLM."
  (let* ((sandbox (rlm-env-sandbox env))
         (bindings (sandbox-definitions sandbox)))
    (map (lambda (pair)
           (let* ((name (car pair))
                  (val (cdr pair))
                  (val-str (if (procedure? val)
                               "#<procedure>"
                               (catch #t
                                 (lambda ()
                                   (let ((str (format #f "~a" val)))
                                     (if (> (string-length str) 100)
                                         (string-append (substring str 0 97) "...")
                                         str)))
                                 (lambda _ "#<error>")))))
             (cons name val-str)))
         bindings)))

;; Keep analyze-parentheses for syntax check compatibility
(define (analyze-parentheses code-string)
  "Counts opening and closing parentheses, ignoring strings and comments.
Returns a pair: (missing-closing-parens-count . hint-string)."
  (let loop ((chars (string->list code-string))
             (in-string? #f)
             (in-comment? #f)
             (escape? #f)
             (open-parens 0)
             (close-parens 0))
    (if (null? chars)
        (cond
         ((> open-parens close-parens)
          (cons (- open-parens close-parens)
                (format #f "Syntax Error Hint: You have ~a opening '(' but only ~a closing ')'. You are missing ~a closing parentheses!"
                        open-parens close-parens (- open-parens close-parens))))
         ((< open-parens close-parens)
          (cons 0
                (format #f "Syntax Error Hint: You have ~a opening '(' and ~a closing ')'. You have ~a extra closing parentheses!"
                        open-parens close-parens (- close-parens open-parens))))
         (else (cons 0 #f)))
        (let ((c (car chars))
              (rest (cdr chars)))
          (cond
           (escape? (loop rest in-string? in-comment? #f open-parens close-parens))
           (in-comment?
            (if (char=? c #\newline)
                (loop rest in-string? #f #f open-parens close-parens)
                (loop rest in-string? #t #f open-parens close-parens)))
           (in-string?
            (cond
             ((char=? c #\\) (loop rest in-string? in-comment? #t open-parens close-parens))
             ((char=? c #\") (loop rest #f in-comment? #f open-parens close-parens))
             (else (loop rest in-string? in-comment? #f open-parens close-parens))))
           (else
            (cond
             ((char=? c #\;) (loop rest in-string? #t #f open-parens close-parens))
             ((char=? c #\") (loop rest #t in-comment? #f open-parens close-parens))
             ((char=? c #\() (loop rest in-string? in-comment? #f (+ open-parens 1) close-parens))
             ((char=? c #\)) (loop rest in-string? in-comment? #f open-parens (+ close-parens 1)))
             (else (loop rest in-string? in-comment? #f open-parens close-parens)))))))))
