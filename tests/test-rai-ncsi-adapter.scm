;;; Real HTTP-over-UDS integration tests for the GAIA RAI NCSI transport.

(use-modules (ice-9 popen)
             (ice-9 rdelim)
             (gaia cognitive-session)
             (gaia rai-ncsi-adapter)
             (gaia workspace))

(define (assert-true label value)
  (unless value (error "Assertion failed" label value)))

(define (assert-equal label expected actual)
  (unless (equal? expected actual)
    (error "Assertion failed" label expected actual)))

(define (start-mock-sidecar socket-path request-id status)
  (let* ((script (string-append (dirname (current-filename))
                                "/mock-ncsi-sidecar.py"))
         (port (open-pipe* OPEN_READ "python3" script socket-path request-id
                           (number->string status))))
    (assert-equal "mock sidecar readiness" "READY" (read-line port))
    port))

(define socket-path "/tmp/gaia-rai-ncsi-test.sock")

(let* ((server (start-mock-sidecar socket-path "observation-request" 200))
       (session (make-cognitive-session))
       (client (make-rai-ncsi-client session #:socket-path socket-path))
       (result (rai-ncsi-generate!
                client "prompt" "fixture-model"
                #:mode 'OBSERVATION_ONLY
                #:request-id "observation-request"
                #:lens-id "fixture-lens"
                #:max-new-tokens 1)))
  (assert-equal "observation-only final text" "hello" (assoc-ref result 'final-text))
  (assert-equal "one observation" 1 (assoc-ref result 'observation-count))
  (assert-equal "observation-only has no proposals" 0
                (length (workspace-candidates (session-workspace session))))
  (assert-equal "mock sidecar exited" 0 (close-pipe server)))

(let* ((server (start-mock-sidecar socket-path "policy-request" 200))
       (session (make-cognitive-session))
       (client (make-rai-ncsi-client session #:socket-path socket-path))
       (result (rai-ncsi-generate!
                client "prompt" "fixture-model"
                #:mode 'NCSI_POLICY
                #:request-id "policy-request"
                #:lens-id "fixture-lens"
                #:max-new-tokens 1)))
  (assert-equal "policy final text" "hello" (assoc-ref result 'final-text))
  (assert-equal "bounded policy proposal" 1
                (length (workspace-candidates (session-workspace session))))
  (assert-equal "mock sidecar exited" 0 (close-pipe server)))

(let* ((server (start-mock-sidecar socket-path "failure-request" 500))
       (session (make-cognitive-session))
       (client (make-rai-ncsi-client
                session #:socket-path socket-path
                #:fallback (lambda (_prompt _model) "fallback text")))
       (result (rai-ncsi-generate!
                client "prompt" "fixture-model"
                #:mode 'TEXT_ONLY
                #:request-id "failure-request"
                #:max-new-tokens 1)))
  (assert-equal "fallback mode" 'FALLBACK (assoc-ref result 'mode))
  (assert-equal "fallback output" "fallback text" (assoc-ref result 'final-text))
  (assert-equal "mock sidecar exited" 0 (close-pipe server)))

(when (file-exists? socket-path) (delete-file socket-path))
(display "RAI NCSI HTTP-over-UDS integration tests passed\n")
(exit 0)
