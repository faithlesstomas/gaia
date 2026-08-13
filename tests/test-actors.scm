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

(define (get-models-mock)
  '("gemma4:e2b" "gpt-4o"))

(let ((mod (resolve-module '(gaia llm-client) #:ensure #f)))
  (when mod
    (module-set! mod 'chat-with-llm chat-with-llm-mock)
    (module-set! mod 'get-models get-models-mock)))


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
                [(chat session-id prompt model system-prompt think history stream-callback #:optional (role "user"))
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
         (set! orchestrator (spawn ^session-orchestrator "session-orch-test" mock-socket channel (lambda (expr) #t) sandbox-actor agent-actor llm-client '() "gemma4:e2b" #t)))

       (with-vat session-vat
         (<- orchestrator 'handle-message '(get-model))
         (<- orchestrator 'handle-message '(set-model "gemma4-think"))
         (<- orchestrator 'handle-message '(list-models))
         (<- orchestrator 'handle-message '(get-thinking))
         (<- orchestrator 'handle-message '(set-thinking "on"))
         (<- orchestrator 'handle-message 'interrupt)
         (<- orchestrator 'handle-message '(get-history)))
       (let loop ()
         (set! output-val (get-output-string mock-socket))
         (if (and (string-contains output-val "model-info")
                  (string-contains output-val "models-list")
                  (string-contains output-val "thinking-info")
                  (string-contains output-val "history-list"))
             (with-vat session-vat
               (on (<- orchestrator 'handle-message 'eof)
                   (lambda (_) (set! done? #t))))
             (begin
               (sleep 0.01)
               (loop)))))
     #:drain? #t)
    (and (port-closed? mock-socket)
         (string-contains output-val "model-info")
         (string-contains output-val "models-list")
         (string-contains output-val "thinking-info")
         (string-contains output-val "history-list"))))


;; --- 5. Test actors.scm clean-history and replay-history helpers ---

(test-group "actors helpers"
  (test-assert "clean-history: strips assistant think tags, preserves user content"
    (let* ((history `((("role" . "user")      ("content" . "Hello <think>leak</think>"))
                      (("role" . "assistant") ("content" . "<think>thinking...</think>Yes, hello."))))
           (cleaned ((@@ (gaia actors) clean-history) history)))
      (and
       ;; User content left intact (including think tag)
       (string-contains (assoc-ref (car cleaned) "content") "<think>")
       ;; Assistant content cleaned
       (string=? (assoc-ref (cadr cleaned) "content") "Yes, hello."))))

  (test-assert "clean-history: strips assistant code blocks"
    (let* ((history `((("role" . "assistant") ("content" . "```repl\n(define x 1)\n``` FINAL(done)"))))
           (cleaned ((@@ (gaia actors) clean-history) history)))
      ;; clean-assistant-content strips code blocks and final signals
      (string=? (assoc-ref (car cleaned) "content") "")))

  (test-assert "replay-history: executes repl blocks from assistant turns"
    (let* ((env (make-rlm-env "session-replay-actors"))
           (history `((("role" . "user")      ("content" . "Set x"))
                      (("role" . "assistant") ("content" . "```repl\n(define replayed-actors-var 777)\n```")))))
      ((@@ (gaia actors) replay-history) env history)
      (equal? (rlm-eval! env "replayed-actors-var") '(ok "777"))))

  (test-assert "replay-history: skips non-assistant turns"
    (let* ((env (make-rlm-env "session-replay-skip"))
           (history `((("role" . "user") ("content" . "```repl\n(define should-not-run 999)\n```")))))
      ((@@ (gaia actors) replay-history) env history)
      ;; user turn repl block should NOT be executed
      (match (rlm-eval! env "should-not-run")
        (('error . _) #t)
        (_ #f)))))

(define (run-direct-coverage-tests)
  (let* ((gcore (resolve-module '(goblins core)))
         (goblins-mod (resolve-module '(goblins)))
         (actors-mod (resolve-module '(gaia actors)))
         (threads-mod (resolve-module '(ice-9 threads) #:ensure #f))
         
         ;; Create a real transactormap and syscaller
         ;; make-syscaller takes (actormap) in older goblins, (actormap sleep-profile) in 0.18+
         (am (make-transactormap (make-whactormap)))
         (sys (let* ((f (@@ (goblins core) make-syscaller))
                     (arity (procedure-minimum-arity f))
                     (n-args (car arity)))
                (if (= n-args 1)
                    (f am)
                    (f am #f))))
         
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
                             (lambda* (session-id prompt model system-prompt #:key think history stream-callback #:allow-other-keys)
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
                      [(chat session-id prompt model system-prompt think history stream-callback #:optional (role "user"))
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

          ;; Test agent-actor diagnostic bailout mechanism
          (let* ((sandbox (spawn ^repl-sandbox "bailout-agent-session" (lambda _ #t) (lambda _ #t) '()))
                 (resp-ptr 0)
                 (llm-responses
                  '("```repl\n(unbound-var-1)\n```"
                    "```repl\n(unbound-var-2)\n```"
                    "```repl\n(unbound-var-3)\n```"
                    "FINAL(Diagnostic Fix Answer) CONFIDENCE(100)"))
                 (mock-llm
                  (spawn
                   (lambda (bcom)
                     (methods
                      [(chat session-id prompt model system-prompt think history stream-callback #:optional (role "user"))
                       (let ((resp (if (string-contains prompt "consecutive errors")
                                       "FINAL(Diagnostic Fix Answer) CONFIDENCE(100)"
                                       (let ((r (list-ref llm-responses resp-ptr)))
                                         (set! resp-ptr (+ resp-ptr 1))
                                         r))))
                         (let-values (((promo resolver) (spawn-promise-and-resolver)))
                           (<-np resolver 'fulfill
                                 `(("payload" . (("content" . ,resp)
                                                 ("reasoning" . "Thinking...")))))
                           promo))]))))
                 (agent (spawn ^agent-actor "bailout-agent-session" sandbox mock-llm (lambda _ #t) (lambda _ #t)))
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
            
            (<- agent 'solve "Perform task with failures" 0 '() resolver)
            (run-turns-synchronously)
            (test-assert "direct-agent-actor: diagnostic bailout triggers on consecutive errors"
              (and resolved? (string-contains (car result-val) "Diagnostic Fix Answer"))))
          
          ;; 4. Test session-orchestrator behavior directly
          (let* ((sandbox (spawn ^repl-sandbox "direct-orch-session" (lambda _ #t) (lambda _ #t) '()))
                 (mock-llm
                  (spawn
                   (lambda (bcom)
                      (methods
                       [(chat session-id prompt model system-prompt think history stream-callback #:optional (role "user"))
                        (let-values (((promo resolver) (spawn-promise-and-resolver)))
                          (<-np resolver 'fulfill
                                `(("payload" . (("content" . "Mocked answer")
                                                ("reasoning" . "Thinking...")))))
                          promo)]
                        [(get-models)
                         (let-values (((promo resolver) (spawn-promise-and-resolver)))
                           (<-np resolver 'fulfill '("gemma4:e2b" "gpt-4o"))
                           promo)]))))
                 (agent (spawn ^agent-actor "direct-orch-session" sandbox mock-llm (lambda _ #t) (lambda _ #t)))
                 (mock-socket (open-output-string))
                 (mock-channel #f)
                 (orch (spawn ^session-orchestrator "direct-orch-session" mock-socket mock-channel (lambda (expr) #t) sandbox agent mock-llm '() "gemma4:e2b" #t)))
            
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
                (<- orch 'handle-message '(help))
                (run-turns-synchronously)
                (<- orch 'handle-message 'eof)
                (run-turns-synchronously)
                (port-closed? mock-socket))))
            
            ;; 5. Test session-orchestrator eval command (non-recursive notebook mode)
            (let* ((sandbox (spawn ^repl-sandbox "direct-eval-session" (lambda _ #t) (lambda _ #t) '()))
                   (mock-llm
                    (spawn
                     (lambda (bcom)
                       (methods
                        [(chat session-id prompt model system-prompt think history stream-callback #:optional (role "user"))
                         (let-values (((promo resolver) (spawn-promise-and-resolver)))
                           (<-np resolver 'fulfill
                                 `(("payload" . (("content" . "Let's run some code:\n```repl\n(define eval-var 888)\n```")
                                                 ("reasoning" . "Reasoning...")))))
                           promo)]))))
                   (agent (spawn ^agent-actor "direct-eval-session" sandbox mock-llm (lambda _ #t) (lambda _ #t)))
                   (mock-socket (open-output-string))
                   (mock-channel #f)
                   (orch (spawn ^session-orchestrator "direct-eval-session" mock-socket mock-channel (lambda (expr) #t) sandbox agent mock-llm '() "gemma4:e2b" #t)))
              (test-assert "direct-orchestrator: eval (notebook mode) runs code block once and sends notebook-done"
                (begin
                  (<- orch 'handle-message '(eval "run this code"))
                  (run-turns-synchronously)
                  ;; A direct REPL request must enter the session GCAS cycle as
                  ;; Action → ActionCompleted, rather than bypassing it.
                  (<- orch 'handle-message '(repl "(+ 20 22)"))
                  (run-turns-synchronously)
                  (<- orch 'handle-message '(get-cognitive-events))
                  (run-turns-synchronously)
                  (let ((output (get-output-string mock-socket)))
                    (and (string-contains output "code")
                         (string-contains output "result")
                         (string-contains output "notebook-done")
                         (string-contains output "ActionCompleted"))))))

            ;; 6. Test session-orchestrator solve command (recursive solver mode)
            (let* ((sandbox (spawn ^repl-sandbox "direct-solve-session" (lambda _ #t) (lambda _ #t) '()))
                   (llm-calls 0)
                   (mock-llm
                    (spawn
                     (lambda (bcom)
                       (methods
                        [(chat session-id prompt model system-prompt think history stream-callback #:optional (role "user"))
                         (set! llm-calls (+ llm-calls 1))
                         (let-values (((promo resolver) (spawn-promise-and-resolver)))
                           (<-np resolver 'fulfill
                                 `(("payload" . (("content" . ,(if (= llm-calls 1)
                                                                   "Run code:\n```repl\n(define solve-var 999)\n```"
                                                                   "FINAL(999) CONFIDENCE(100)"))
                                                 ("reasoning" . "Reasoning...")))))
                           promo)]))))
                   (agent (spawn ^agent-actor "direct-solve-session" sandbox mock-llm (lambda _ #t) (lambda _ #t)))
                   (mock-socket (open-output-string))
                   (mock-channel #f)
                   (orch (spawn ^session-orchestrator "direct-solve-session" mock-socket mock-channel (lambda (expr) #t) sandbox agent mock-llm '() "gemma4:e2b" #t)))
              (test-assert "direct-orchestrator: solve (solver mode) runs recursively until final answer"
                (begin
                  (<- orch 'handle-message '(solve "run this solve"))
                  (run-turns-synchronously)
                  (let ((output (get-output-string mock-socket)))
                    (and (string-contains output "code")
                         (string-contains output "result")
                         (string-contains output "final")
                         (> llm-calls 1))))))))
      
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
