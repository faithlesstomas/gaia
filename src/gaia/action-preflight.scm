(define-module (gaia action-preflight)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-13)
  #:use-module (language wisp spec)
  #:use-module (system base language)
  #:export (<action-preflight>
            action-preflight?
            action-preflight-valid?
            action-preflight-error-class
            action-preflight-message
            action-preflight-failing-form
            action-preflight-forms
            preflight-action))

(define-record-type <action-preflight>
  (%make-action-preflight valid? error-class message failing-form forms)
  action-preflight?
  (valid? action-preflight-valid?)
  (error-class action-preflight-error-class)
  (message action-preflight-message)
  (failing-form action-preflight-failing-form)
  (forms action-preflight-forms))

(define (read-scheme-forms text)
  (call-with-input-string text
    (lambda (port)
      (let loop ((forms '()))
        (let ((form (read port)))
          (if (eof-object? form)
              (reverse forms)
              (loop (cons form forms))))))))

(define (read-wisp-forms text)
  (let* ((body (string-drop text (string-length ";; wisp")))
         (reader (language-reader (lookup-language 'wisp))))
    (call-with-input-string body
      (lambda (port)
        (let loop ((forms '()))
          (let ((form (reader port #f)))
            (if (eof-object? form)
                (reverse forms)
                (loop (cons form forms)))))))))

(define (failure error-class key args failing-form)
  (%make-action-preflight
   #f error-class
   (format #f "~a: ~s" key args)
   failing-form
   '()))

(define (preflight-action text)
  "Parse and macro-expand a complete Action without evaluating or mutating it."
  (if (or (not (string? text)) (string-null? (string-trim-both text)))
      (%make-action-preflight #f 'INCOMPLETE_ACTION
                              "Action is empty." "<empty>" '())
      (catch #t
        (lambda ()
          (let ((forms (if (string-prefix? ";; wisp" (string-trim-both text))
                           (read-wisp-forms (string-trim-both text))
                           (read-scheme-forms text))))
            (if (null? forms)
                (%make-action-preflight #f 'INCOMPLETE_ACTION
                                        "Action contains no forms." "<empty>" '())
                (begin
                  ;; Macro expansion detects malformed special forms such as a
                  ;; bad let without evaluating user code or mutating state.
                  (macroexpand (cons 'begin forms))
                  (%make-action-preflight #t #f "OK" #f forms)))))
        (lambda (key . args)
          (failure
           (cond
            ((memq key '(read-error wisp-parser-error)) 'READ_SYNTAX)
            ((eq? key 'syntax-error) 'MACRO_SYNTAX)
            (else 'PREFLIGHT_ERROR))
           key args text)))))
