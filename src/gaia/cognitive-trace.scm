(define-module (gaia cognitive-trace)
  #:use-module (ice-9 optargs)
  #:use-module (srfi srfi-13)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-control)
  #:use-module (gaia cognitive-process)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia workspace)
  #:export (trace-preview
            format-cognitive-event-trace
            make-cognitive-trace-sink))

(define* (trace-preview value #:optional (limit 240))
  (let* ((text (format #f "~s" value))
         (single-line
          (string-map (lambda (char)
                        (if (or (char=? char #\newline)
                                (char=? char #\return))
                            #\space char))
                      text)))
    (if (> (string-length single-line) limit)
        (string-append (substring single-line 0 limit) "...")
        single-line)))

(define* (format-cognitive-event-trace session-id session event
                                       #:key (preview-chars 240))
  "Format one durable cognitive event with its current process and Workspace."
  (let* ((payload (event-payload event))
         (workspace (session-workspace session))
         (process (session-current-process session))
         (control (if process (process-control process) (session-control session)))
         (payload-summary
          (if (cognitive-object? payload)
              (format #f
                      "co={id=~a type=~a provenance=~a epistemic=~a verification=~a relations=~s content=~a}"
                      (co-id payload) (co-type payload) (co-provenance payload)
                      (co-epistemic-status payload) (co-verification-status payload)
                      (co-relations payload)
                      (trace-preview (co-content payload) preview-chars))
              (format #f "payload=~a"
                      (trace-preview payload preview-chars)))))
    (format #f
            "[GCAS][~a] event=~a origin=~a ~a process={id=~a active=~a outcome=~a} control={transitions=~a progress=~a failures=~a termination=~a} workspace={pending=~s active=~s}"
            session-id (event-type event) (event-origin event) payload-summary
            (and process (process-id process))
            (and process (process-active? process))
            (and process (process-outcome process))
            (control-transition-count control)
            (control-progress-count control)
            (control-failure-count control)
            (control-termination-reason control)
            (map co-id (workspace-candidates workspace))
            (map co-id (workspace-active workspace)))))

(define* (make-cognitive-trace-sink session-id logger
                                    #:key (preview-chars 240))
  "Return a trace sink which sends formatted durable events to LOGGER."
  (unless (procedure? logger)
    (error "Cognitive trace logger must be a procedure" logger))
  (lambda (session event)
    (logger (format-cognitive-event-trace
             session-id session event #:preview-chars preview-chars))))
