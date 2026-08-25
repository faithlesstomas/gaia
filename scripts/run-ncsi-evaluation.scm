#!/usr/bin/env -S guile -L src -s
!#

(use-modules (ice-9 rdelim)
             (ice-9 textual-ports)
             (gaia cognitive-session)
             (gaia ncsi-evaluation)
             (gaia rai-ncsi-adapter)
             (gaia utils))

(define (env-number name fallback parser)
  (let ((value (getenv name)))
    (if value (parser value) fallback)))

(define (env-layers)
  (let ((value (getenv "GAIA_NCSI_LAYERS")))
    (if value
        (map string->number (string-split value #\,))
        '())))

(define (load-tasks path)
  (call-with-input-file path
    (lambda (port) (vector->list (json->scm (read-string port))))))

(define (main args)
  (let* ((tasks-path (or (getenv "GAIA_NCSI_EVAL_TASKS")
                         "tests/fixtures/ncsi/gcas.ncsi.eval.v1.json"))
         (output-path (or (getenv "GAIA_NCSI_EVAL_OUTPUT")
                          "ncsi-evaluation-report.json"))
         (socket-path (or (getenv "GAIA_NCSI_SOCKET")
                          (let ((runtime (getenv "XDG_RUNTIME_DIR")))
                            (and runtime (string-append runtime "/rai/neural.sock")))
                          "/tmp/rai-neural.sock"))
         (model (or (getenv "GAIA_NCSI_MODEL")
                    "HuggingFaceTB/SmolLM2-135M"))
         (lens-id (or (getenv "GAIA_NCSI_LENS") "smollm2-jlens-v1"))
         (repeats (env-number "GAIA_NCSI_REPEATS" 2 string->number))
         (tasks (load-tasks tasks-path))
         (options `((max-new-tokens . ,(env-number "GAIA_NCSI_MAX_NEW_TOKENS"
                                                   32 string->number))
                    (timeout-seconds . ,(env-number "GAIA_NCSI_TIMEOUT"
                                                  120 string->number))
                    (top-k . ,(env-number "GAIA_NCSI_TOP_K" 8 string->number))
                    (layers . ,(env-layers))
                    (run-id . ,(format #f "~a-~a" (current-time)
                                       (random 1000000)))))
         (client-factory
          (lambda (session)
            (make-rai-ncsi-client session #:socket-path socket-path)))
         (results (run-ncsi-evaluation tasks client-factory model lens-id
                                       #:repeats repeats #:options options))
         (summary (summarize-ncsi-evaluation results))
         (report `(("summary" . ,summary)
                   ("results" . ,(list->vector results)))))
    (call-with-output-file output-path
      (lambda (port)
        (display (scm->json report) port)
        (newline port)))
    (display (scm->json summary))
    (newline)
    0))

(exit (main (command-line)))
