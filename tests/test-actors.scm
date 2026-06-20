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
             (gaia utils)
             (goblins core-types))

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

(define (run-direct-coverage-tests)
  (let* ((gcore (resolve-module '(goblins core)))
         (goblins-mod (resolve-module '(goblins)))
         (actors-mod (resolve-module '(gaia actors)))
         (threads-mod (resolve-module '(ice-9 threads) #:ensure #f))
         
         ;; Create a real transactormap and syscaller
         (am (make-transactormap (make-whactormap)))
         (sys ((@@ (goblins core) make-syscaller) am #f))
         
         ;; Save original actors bindings
         (orig-call-with-vat (module-ref goblins-mod 'call-with-vat))
         (orig-spawn-vat (module-ref actors-mod 'spawn-vat))
         (orig-call-with-new-thread (and threads-mod (module-ref threads-mod 'call-with-new-thread))))
    
    (define (run-turns-synchronously)
      (sleep 0.05)
      (let loop ()
        (let ((msgs ((@@ (goblins core) syscaller-new-msgs) sys)))
          (unless (null? msgs)
            ((@@ (goblins core) set-syscaller-new-msgs!) sys '())
            (for-each
             (lambda (msg)
               (let-values (((result buffer-am new-msgs)
                             ((@@ (goblins core) actormap-turn-message)
                              ((@@ (goblins core) syscaller-actormap) sys) msg #:catch-errors? #t)))
                 (unless ((@@ (goblins core-types) transactormap-merged?) buffer-am)
                   ((@@ (goblins core) transactormap-buffer-merge!) buffer-am))
                 (for-each (lambda (m) ((@@ (goblins core) syscaller-queue-new-msg!) sys m))
                           new-msgs)))
             (reverse msgs))
            (loop)))))

    (define (mock-binding! mod symbol new-value)
      (let ((var (module-variable mod symbol)))
        (if var
            (variable-set! var new-value)
            (module-define! mod symbol new-value))))
    
    (run-fibers
     (lambda ()
       (dynamic-wind
      (lambda ()
        ;; Install actors mocks
        (mock-binding! actors-mod 'spawn-vat
                       (lambda () 'mock-sub-vat))
        
        (mock-binding! goblins-mod 'call-with-vat
                       (lambda (vat thunk)
                         (thunk)))
        
        ;; Replace POSIX thread with fiber so VM coverage hook captures it
        (when threads-mod
          (mock-binding! threads-mod 'call-with-new-thread
                         (lambda (thunk) (spawn-fiber thunk) #f))))
      
      (lambda ()
        (parameterize (((@@ (goblins core) current-syscaller) sys)
                       (current-<-np-extern
                        (lambda (refr . args)
                          (parameterize (((@@ (goblins core) current-syscaller) sys))
                            (apply <-np refr args)))))
          
          ;; 1. Test repl-sandbox behavior directly
          (let* ((sandbox (spawn ^repl-sandbox "direct-session" (lambda _ #t) (lambda _ #t) '())))
            
            (test-assert "direct-sandbox: eval"
              (let* ((vow (<- sandbox 'eval "(define x-direct 100) (+ x-direct 5)"))
                     (res #f))
                (run-turns-synchronously)
                (on vow (lambda (val) (set! res val)))
                (run-turns-synchronously)
                (match res
                  (('ok "105") #t)
                  (other (begin (display (format #f "eval failed: ~s\n" other)) #f)))))
            
            (test-assert "direct-sandbox: definitions"
              (let* ((vow (<- sandbox 'definitions))
                     (res #f))
                (run-turns-synchronously)
                (on vow (lambda (val) (set! res val)))
                (run-turns-synchronously)
                (and (list? res) (assq 'x-direct res))))
            
            (test-assert "direct-sandbox: save/restore checkpoint"
              (let* ((vow-cp (<- sandbox 'save-checkpoint))
                     (cp #f))
                (run-turns-synchronously)
                (on vow-cp (lambda (val) (set! cp val)))
                (run-turns-synchronously)
                (<- sandbox 'eval "(define x-direct 200)")
                (run-turns-synchronously)
                (<- sandbox 'restore-checkpoint cp)
                (run-turns-synchronously)
                (let* ((vow-val (<- sandbox 'eval "x-direct"))
                       (final-val #f))
                  (run-turns-synchronously)
                  (on vow-val (lambda (val) (set! final-val val)))
                  (run-turns-synchronously)
                  (match final-val
                    (('ok "100") #t)
                    (_ #f)))))
            
            (test-assert "direct-sandbox: fork"
              (let* ((vow-fork (<- sandbox 'fork))
                     (forked-sandbox #f))
                (run-turns-synchronously)
                (on vow-fork (lambda (val) (set! forked-sandbox val)))
                (run-turns-synchronously)
                (let* ((vow-val (<- forked-sandbox 'eval "x-direct"))
                       (final-val #f))
                  (run-turns-synchronously)
                  (on vow-val (lambda (val) (set! final-val val)))
                  (run-turns-synchronously)
                  (match final-val
                    (('ok "100") #t)
                    (_ #f))))))
          
          ;; 2. Test llm-client behavior directly
          (let* ((orig-chat (@@ (gaia llm-client) chat-with-llm))
                 (llm-mod (resolve-module '(gaia llm-client))))
            (dynamic-wind
              (lambda ()
                (module-set! llm-mod 'chat-with-llm
                             (lambda* (session-id prompt model system-prompt #:key think history stream-callback)
                               `(("payload" . (("content" . "Hello! I am a mocked response.")
                                               ("reasoning" . "Thinking...")))))))
              (lambda ()
                (let* ((llm (spawn ^llm-client #f))
                       (vow (<- llm 'chat "session-id" "prompt" "model" "system" #f '() #f))
                       (res #f))
                  (run-turns-synchronously)
                  (on vow (lambda (val) (set! res val)))
                  (run-turns-synchronously)
                  (test-assert "direct-llm-client: chat"
                    (equal? (assoc-ref res "payload")
                            '(("content" . "Hello! I am a mocked response.")
                              ("reasoning" . "Thinking..."))))))
              (lambda ()
                (module-set! llm-mod 'chat-with-llm orig-chat))))
          
          ;; 3. Test agent-actor behavior directly
          (let* ((sandbox (spawn ^repl-sandbox "direct-agent-session" (lambda _ #t) (lambda _ #t) '()))
                 (resp-ptr 0)
                 (llm-responses
                  '("```delegate\n(delegate \"Sub-task\" \"Some context\")\n```"
                    "I will write code.\n```repl\n(define foo-agent 999)\n```"
                    "FINAL(The agent value is 999) CONFIDENCE(100)"
                    "FINAL(The agent value is 999) CONFIDENCE(100)"))
                 (mock-llm
                  (spawn
                   (lambda (bcom)
                     (methods
                      [(chat session-id prompt model system-prompt think history stream-callback)
                       (let ((resp (list-ref llm-responses resp-ptr)))
                         (set! resp-ptr (+ resp-ptr 1))
                         (let-values (((promo resolver) (spawn-promise-and-resolver)))
                           (<-np resolver 'fulfill
                                 `(("payload" . (("content" . ,resp)
                                                 ("reasoning" . "Thinking...")))))
                           promo))]))))
                 (agent (spawn ^agent-actor "direct-agent-session" sandbox mock-llm (lambda _ #t) (lambda _ #t)))
                 (resolved? #f)
                 (result-val #f)
                 (resolver
                  (spawn
                   (lambda (bcom)
                     (methods
                      [(fulfill val)
                       (set! resolved? #t)
                       (set! result-val val)]
                      [(break err)
                       (set! resolved? #t)
                       (set! result-val err)])))))
            
            (<- agent 'solve "What is the agent value?" 0 '() resolver)
            (run-turns-synchronously)
            (test-assert "direct-agent-actor: solve recursive loop"
              (and resolved? (equal? (car result-val) "The agent value is 999"))))
          
          ;; 4. Test session-orchestrator behavior directly
          (let* ((sandbox (spawn ^repl-sandbox "direct-orch-session" (lambda _ #t) (lambda _ #t) '()))
                 (mock-llm
                  (spawn
                   (lambda (bcom)
                     (methods
                      [(chat session-id prompt model system-prompt think history stream-callback)
                       (let-values (((promo resolver) (spawn-promise-and-resolver)))
                         (<-np resolver 'fulfill
                               `(("payload" . (("content" . "Mocked answer")
                                               ("reasoning" . "Thinking...")))))
                         promo)]))))
                 (agent (spawn ^agent-actor "direct-orch-session" sandbox mock-llm (lambda _ #t) (lambda _ #t)))
                 (mock-socket (open-output-string))
                 (mock-channel #f)
                 (orch (spawn ^session-orchestrator "direct-orch-session" mock-socket mock-channel sandbox agent mock-llm '())))
            
            (test-assert "direct-orchestrator: handle-message commands"
              (begin
                (<- orch 'handle-message '(get-model))
                (run-turns-synchronously)
                (<- orch 'handle-message '(set-model "new-model-name"))
                (run-turns-synchronously)
                (<- orch 'handle-message '(list-models))
                (run-turns-synchronously)
                (<- orch 'handle-message '(get-thinking))
                (run-turns-synchronously)
                (<- orch 'handle-message '(set-thinking "on"))
                (run-turns-synchronously)
                (<- orch 'handle-message 'interrupt)
                (run-turns-synchronously)
                (<- orch 'handle-message '(get-history))
                (run-turns-synchronously)
                (<- orch 'handle-message '(session ""))
                (run-turns-synchronously)
                (<- orch 'handle-message '(session "new-session-id"))
                (run-turns-synchronously)
                (<- orch 'handle-message '(list-sessions))
                (run-turns-synchronously)
                (<- orch 'handle-message 'eof)
                (run-turns-synchronously)
                (port-closed? mock-socket))))))
      
      (lambda ()
        ;; Restore original actors bindings
        (mock-binding! goblins-mod 'call-with-vat orig-call-with-vat)
        (mock-binding! actors-mod 'spawn-vat orig-spawn-vat)
        (when (and threads-mod orig-call-with-new-thread)
          (mock-binding! threads-mod 'call-with-new-thread orig-call-with-new-thread)))))
     #:drain? #t)))

(test-group "Direct Thread Coverage"
  (run-direct-coverage-tests))

(test-end "gaia-actors")
