(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (srfi srfi-64)
             (srfi srfi-11)
             (goblins)
             (goblins actor-lib methods)
             (ice-9 match)
             (fibers)
             (fibers channels)
             (gaia actors)
             (gaia sandbox)
             (gaia executor)
             (gaia rlm-env)
             (gaia llm-client)
             (gaia utils))

(test-begin "gaia-actors")

;; --- Common Mocks ---

(define (chat-with-llm-mock session-id input model system-prompt . args)
  `(("payload" . (("content" . "Hello! I am a mocked response.")
                  ("reasoning" . "Thinking...")))))

(let ((mod (resolve-module '(gaia llm-client) #:ensure #f)))
  (when mod
    (module-set! mod 'chat-with-llm chat-with-llm-mock)))


;; --- 1. Test repl-sandbox actor ---

(test-assert "repl-sandbox actor lifecycle and methods"
  (let* ((session-vat (spawn-vat))
         (done? #f)
         (eval-res #f)
         (defs-res #f)
         (checkpoint-res #f))
    (run-fibers
     (lambda ()
       (let ((sandbox (with-vat session-vat
                        (spawn ^repl-sandbox "session-sandbox-test" 
                               (lambda (evt) #t) 
                               (lambda (expr) #t) 
                               '()))))
         (with-vat session-vat
           (on (<- sandbox 'eval "(define my-test-var 123) (+ my-test-var 1)")
               (lambda (res)
                 (set! eval-res res)
                 ;; Get definitions
                 (on (<- sandbox 'definitions)
                     (lambda (defs)
                       (set! defs-res defs)
                       ;; Save checkpoint
                       (on (<- sandbox 'save-checkpoint)
                           (lambda (cp)
                             (set! checkpoint-res cp)
                             ;; Mutate state and then restore checkpoint
                             (on (<- sandbox 'eval "(define my-test-var 456)")
                                 (lambda (_)
                                   (on (<- sandbox 'restore-checkpoint cp)
                                       (lambda (restore-status)
                                         ;; Check if restored variable value has rolled back
                                         (on (<- sandbox 'eval "my-test-var")
                                             (lambda (final-val)
                                               (set! done? #t)
                                               (set! eval-res (list eval-res defs-res restore-status final-val))))))))))))))))
       (let loop ()
         (unless done?
           (sleep 0.01)
           (loop))))
     #:drain? #t)
    (match eval-res
      ((('ok "124") defs 'ok ('ok "123"))
       (and (list? defs) (assq 'my-test-var defs)))
      (_ #f))))


;; --- 2. Test repl-sandbox fork method ---

(test-assert "repl-sandbox fork creates a cloned environment"
  (let* ((session-vat (spawn-vat))
         (done? #f)
         (result #f))
    (run-fibers
     (lambda ()
       (let ((sandbox (with-vat session-vat
                        (spawn ^repl-sandbox "session-fork-test"
                               (lambda (evt) #t)
                               (lambda (expr) #t)
                               '()))))
         (with-vat session-vat
           ;; Define a variable
           (on (<- sandbox 'eval "(define forked-var \"hello-fork\")")
               (lambda (_)
                 ;; Fork it
                 (on (<- sandbox 'fork)
                     (lambda (forked-sandbox)
                       ;; Evaluate in fork
                       (on (<- forked-sandbox 'eval "forked-var")
                           (lambda (fork-val)
                             (set! result fork-val)
                             (set! done? #t)))))))))
       (let loop ()
         (unless done?
           (sleep 0.01)
           (loop))))
     #:drain? #t)
    (equal? result '(ok "\"hello-fork\""))))


;; --- 3. Test agent-actor solve & step-by-step logic ---

;; Helper actor to run solve and return a promise, providing a proper syscaller context
(define-actor (^test-resolver bcom agent)
  (methods
   [(run-solve task)
    (let-values (((solve-p resolve-solve) (spawn-promise-and-resolver)))
      (<- agent 'solve task 0 '() resolve-solve)
      solve-p)]))

(test-assert "agent-actor recursion, code execution, and final answer extraction"
  (let* ((session-vat (spawn-vat))
         (done? #f)
         (result #f)
         (agent-history '())
         (llm-responses
          '("I will write code.\n```repl\n(define foo-agent 999)\n```"
            "FINAL(The agent value is 999) CONFIDENCE(100)"))
         (resp-ptr 0)
         ;; Mock chat method to step through LLM responses
         (mock-llm-client
          (with-vat session-vat
            (spawn
             (lambda (bcom)
               (methods
                [(chat session-id prompt model system-prompt think history stream-callback)
                 (let ((resp (list-ref llm-responses resp-ptr)))
                   (set! resp-ptr (+ resp-ptr 1))
                   (let-values (((promo resolver) (spawn-promise-and-resolver)))
                     (<-np resolver 'fulfill
                           `(("payload" . (("content" . ,resp)
                                           ("reasoning" . "Reasoning...")))))
                     promo))]))))))
    (run-fibers
     (lambda ()
       (let* ((sandbox (with-vat session-vat
                         (spawn ^repl-sandbox "session-agent-test"
                                (lambda (evt) #t)
                                (lambda (expr) #t)
                                '())))
              (agent (with-vat session-vat
                       (spawn ^agent-actor "session-agent-test"
                              sandbox mock-llm-client
                              (lambda (evt) #t)
                              (lambda (expr) #t))))
              (resolver (with-vat session-vat
                          (spawn ^test-resolver agent))))
         (with-vat session-vat
           (on (<- resolver 'run-solve "What is the agent value?")
               (lambda (res-pair)
                 (set! result (car res-pair))
                 (set! agent-history (cdr res-pair))
                 (set! done? #t))))
         (let loop ()
           (unless done?
             (sleep 0.01)
             (loop)))))
     #:drain? #t)
    (and (equal? result "The agent value is 999")
         (pair? agent-history))))


;; --- 4. Test session-orchestrator actor and handle-message commands ---

(test-assert "session-orchestrator handle-message commands"
  (let* ((session-vat (spawn-vat))
         (done? #f)
         (output-val #f)
         ;; Mock a Goblins channel
         (channel (make-channel))
         ;; Mock client socket as an output string port so we can verify sent events
         (mock-socket (open-output-string))
         (sandbox-actor #f)
         (agent-actor #f)
         (llm-client #f)
         (orchestrator #f))
    (run-fibers
     (lambda ()
       (with-vat session-vat
         (set! sandbox-actor (spawn ^repl-sandbox "session-orch-test" (lambda (evt) #t) (lambda (expr) #t) '()))
         (set! llm-client (spawn ^llm-client session-vat))
         (set! agent-actor (spawn ^agent-actor "session-orch-test" sandbox-actor llm-client (lambda (evt) #t) (lambda (expr) #t)))
         (set! orchestrator (spawn ^session-orchestrator "session-orch-test" mock-socket channel sandbox-actor agent-actor llm-client '())))

       (with-vat session-vat
         ;; 1. Test handle-message: get-model
         (<- orchestrator 'handle-message '(get-model))
         ;; 2. Test handle-message: set-model
         (<- orchestrator 'handle-message '(set-model "gemma4-think"))
         ;; 3. Test handle-message: list-models
         (<- orchestrator 'handle-message '(list-models))
         ;; 4. Test handle-message: get-thinking
         (<- orchestrator 'handle-message '(get-thinking))
         ;; 5. Test handle-message: set-thinking
         (<- orchestrator 'handle-message '(set-thinking "on"))
         ;; 6. Test handle-message: interrupt
         (<- orchestrator 'handle-message 'interrupt)
         ;; 7. Test handle-message: get-history
         (on (<- orchestrator 'handle-message '(get-history))
             (lambda (_)
               (set! output-val (get-output-string mock-socket))
               (<- orchestrator 'handle-message 'eof)
               (set! done? #t))))
       (let loop ()
         (unless done?
           (sleep 0.01)
           (loop))))
     #:drain? #t)
    (and (port-closed? mock-socket)
         (string-contains output-val "model-info")
         (string-contains output-val "models-list")
         (string-contains output-val "thinking-info")
         (string-contains output-val "history-list"))))

(test-end "gaia-actors")

