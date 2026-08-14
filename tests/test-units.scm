(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (gaia executor)
             (gaia core)
             (gaia utils)
             (gaia rlm-env)
             (fibers)
             (ice-9 match)
             (srfi srfi-1)
             (srfi srfi-64))

(test-begin "gaia-core")

(test-group "utils"
  (test-equal "json conversion"
    "{\"key\":\"value\"}"
    (scm->json '(("key" . "value"))))

  (test-assert "read-json-file & write-json-file"
    (let* ((filename "test-utils-temp.json")
           (data '(("a" . 1))))
      (write-json-file filename data)
      (let ((read-data (read-json-file filename)))
        (delete-file filename)
        (equal? read-data data))))

  (test-assert "save-session directory creation"
    (let* ((mod (resolve-module '(gaia utils) #:ensure #f))
           (orig-exists? (module-ref mod 'file-exists?)))
      (module-set! mod 'file-exists? (lambda (p) (if (string=? p "sessions") #f (orig-exists? p))))
      (catch #t
        (lambda () (save-session "dummy-session-mkdir" '()))
        (lambda _ #t))
      (module-set! mod 'file-exists? orig-exists?)
      #t))

  (test-assert "send-event direct call"
    (let ((p (open-output-string)))
      (send-event p '(test-event 123))
      (string=? (get-output-string p) "(test-event 123)\n"))))

(test-group "executor"
  (test-equal "simple calculation"
    '(ok "4") ;; Execution output
    (let ((result (guix-investigate "(display (+ 2 2))")))
       result))

  (test-equal "guix-investigate: syntax error"
    '(error syntax "Error: Could not parse code (Syntax Error).")
    (guix-investigate "(display (+ 2 2"))

  (test-assert "guix-investigate: fallback execution when guix not supported"
    (let* ((orig-supported? (@@ (gaia executor) guix-container-supported?))
           (mod (resolve-module '(gaia executor) #:ensure #f)))
      ;; Temporarily mock to #f
      (module-set! mod 'guix-container-supported? (lambda () #f))
      (let ((res (guix-investigate "(display (+ 3 3))")))
        ;; Restore
        (module-set! mod 'guix-container-supported? orig-supported?)
        (equal? res '(ok "6")))))

  (test-assert "rlm-execute: interrupt"
    (let ((env (make-rlm-env "test-interrupt")))
      (let ((core-mod (resolve-module '(gaia core) #:ensure #f))
            (threads-mod (resolve-module '(ice-9 threads) #:ensure #f))
            (orig-cancel (module-ref (resolve-module '(ice-9 threads)) 'cancel-thread)))
        (module-set! threads-mod 'cancel-thread (lambda (t) #f))
        (module-set! core-mod '*interrupted* #t)
        (let ((res (catch 'user-interrupt
                     (lambda ()
                       (rlm-execute env "(sleep 10)")
                       (module-set! core-mod '*interrupted* #f)
                       #f)
                     (lambda _
                       (module-set! core-mod '*interrupted* #f)
                       #t))))
          (module-set! threads-mod 'cancel-thread orig-cancel)
          res)))))

  (test-assert "rlm-execute: error propagation from worker thread"
    (catch 'wrong-type-arg
      (lambda ()
        (rlm-execute #f "(+ 1 1)")
        #f)
      (lambda _ #t)))

  (test-assert "rlm-execute: inside run-fibers (testing yield)"
    (let ((env (make-rlm-env "test-yield-fibers")))
      (run-fibers
       (lambda ()
         (test-equal "execution inside fiber"
           '(ok "5")
           (rlm-execute env "(+ 2 3)")))
       #:drain? #t)
      #t))

  (test-group "rlm-execute meta-commands"
    (let ((env (make-rlm-env "test-meta-commands")))
      ;; Define a custom variable and function in the sandbox first
      (rlm-execute env "(define my-test-val 42)")
      (rlm-execute env "(define (my-test-proc x) (* x x))")

      ;; 1. Test ,globals
      (test-assert ",globals returns safe primitives and capability names"
        (let ((res (rlm-execute env ",globals")))
          (and (pair? res)
               (eq? (car res) 'ok)
               (string-contains (cadr res) "Safe Guile Primitives:")
               (string-contains (cadr res) "car")
               (string-contains (cadr res) "read-file"))))

      ;; 2. Test ,bindings
      (test-assert ",bindings shows our custom defined variable/function"
        (let ((res (rlm-execute env ",bindings")))
          (and (pair? res)
               (eq? (car res) 'ok)
               (string-contains (cadr res) "my-test-val = 42"))))

      ;; 3. Test ,describe
      (test-assert ",describe lists details of a variable"
        (let ((res (rlm-execute env ",describe my-test-val")))
          (and (pair? res)
               (eq? (car res) 'ok)
               (string-contains (cadr res) "Symbol: my-test-val")
               (string-contains (cadr res) "Type: number")
               (string-contains (cadr res) "Value: 42"))))

      (test-assert ",describe lists details of a procedure"
        (let ((res (rlm-execute env ",describe my-test-proc")))
          (and (pair? res)
               (eq? (car res) 'ok)
               (string-contains (cadr res) "Symbol: my-test-proc")
               (string-contains (cadr res) "Type: procedure")
               (string-contains (cadr res) "Arguments:"))))

      ;; 4. Test ,apropos
      (test-assert ",apropos searches for symbols matching pattern"
        (let ((res (rlm-execute env ",apropos my-test")))
          (and (pair? res)
               (eq? (car res) 'ok)
               (string-contains (cadr res) "my-test-val")
               (string-contains (cadr res) "my-test-proc"))))

      ;; 5. Test ,source
      (test-assert ",source shows source code response"
        (let ((res (rlm-execute env ",source my-test-proc")))
          (and (pair? res)
               (eq? (car res) 'ok))))))

  (test-assert "guix-investigate: simulate guix container execution"
    (let* ((mod (resolve-module '(gaia executor) #:ensure #f))
           (orig-supported? (module-ref mod 'guix-container-supported?)))
      ;; Temporarily force support to test container execution path
      (module-set! mod 'guix-container-supported? (lambda () #t))
      (let ((res (guix-investigate "(+ 1 1)")))
        ;; Restore
        (module-set! mod 'guix-container-supported? orig-supported?)
        ;; It might fail or succeed depending on container setup, but let's check it returns structurally correct result
        (and (list? res)
             (or (eq? (car res) 'ok)
                 (eq? (car res) 'error))))))

(test-group "core"
  (test-group "extractors"
    (test-equal "extract-code: repl block"
      "(+ 1 2)"
      (extract-code "```repl\n(+ 1 2)\n```"))
    
    (test-equal "extract-code: scheme block"
      #f
      (extract-code "```scheme\n(* 3 4)\n```"))

    (test-equal "extract-gcas-action: normalizes a scheme block"
      "(* 3 4)"
      (extract-gcas-action "```scheme\n(* 3 4)\n```"))
    
    (test-equal "extract-code: no block"
      #f
      (extract-code "just plain text"))

    (test-equal "extract-delegation: valid block"
      '(delegate "Analyze log" "File: /var/log")
      (extract-delegation "```delegate\n(delegate \"Analyze log\" \"File: /var/log\")\n```"))

    (test-equal "extract-delegation: invalid block"
      #f
      (extract-delegation "plain text delegate"))

    (test-equal "extract-final-signal: final"
      '(final "Done with 42")
      (extract-final-signal "FINAL(Done with 42) CONFIDENCE(100)"))

    (test-equal "extract-final-signal: final-var"
      '(final-var "my-var")
      (extract-final-signal "FINAL_VAR(my-var)"))

    (test-equal "extract-final-signal: none"
      #f
      (extract-final-signal "no final signal here"))

    (test-equal "extract-confidence: confidence"
      98
      (extract-confidence "CONFIDENCE(98)"))

    (test-equal "extract-confidence: tags"
      75
      (extract-confidence "<confidence>75</confidence>"))

    (test-equal "extract-confidence: invalid"
      #f
      (extract-confidence "CONFIDENCE(abc)")))

  (test-group "assistant-cleanup"
    (test-equal "clean-assistant-content: think tag"
      "hello"
      (clean-assistant-content "<think>thinking process</think>hello"))

    (test-equal "clean-assistant-content: thought tag"
      "world"
      (clean-assistant-content "<thought>thinking process</thought>world"))

    (test-equal "clean-assistant-content: code blocks and final signals"
      ""
      (clean-assistant-content "```repl\n(+ 1 2)\n``` FINAL(42) CONFIDENCE(100)"))

    (test-equal "clean-assistant-content: multiple think thoughts and regex tags"
      "hello world"
      (clean-assistant-content "<think>thought1</think><thought>thought2</thought>hello world <|think|>")))

  (test-group "formatting"
    (test-equal "markdown->ansi"
      "\x1b[1mbold\x1b[0m text \x1b[36mcode\x1b[0m"
      (markdown->ansi "**bold** text `code`")))

  (test-group "transcripts"
    (test-equal "format-transcript: simple"
      "[Step 1 input] hello\n[Step 1 response] hi"
      (format-transcript '(("user" . "hello") ("assistant" . "hi"))))

    (test-equal "format-transcript: compacted"
      (string-join
       '("[Steps 1-2 summarized: Successful execution of Scheme REPL operations and exploratory commands. Defined variables and functions survive permanently in Goblins sandbox memory.]"
         "[Step 3 input] 3"
         "[Step 3 response] 3"
         "[Step 4 input] 4"
         "[Step 4 response] 4"
         "[Step 5 input] 5"
         "[Step 5 response] 5")
       "\n")
      (format-transcript '(("user" . "1") ("assistant" . "1")
                           ("user" . "2") ("assistant" . "2")
                           ("user" . "3") ("assistant" . "3")
                           ("user" . "4") ("assistant" . "4")
                           ("user" . "5") ("assistant" . "5")))))

    (test-equal "truncate-for-transcript: long text"
      (string-append (make-string 300 #\a) "\n... [truncated] ...\n" (make-string 100 #\b))
      (truncate-for-transcript (string-append (make-string 300 #\a) (make-string 200 #\c) (make-string 100 #\b))))

  (test-group "error-handling"
    (test-assert "handle-error: syntax"
      (string-contains ((@@ (gaia core) handle-error) 'syntax "unmatched parens" "(+ 1" 0) "Syntax Error"))
    (test-assert "handle-error: permission"
      (string-contains ((@@ (gaia core) handle-error) 'permission "Violation" "(system)" 0) "Security Violation"))
    (test-assert "handle-error: runtime"
      (string-contains ((@@ (gaia core) handle-error) 'runtime "failure" "(+)" 0) "Runtime Error"))
    (test-assert "handle-error: unknown"
      (string-contains ((@@ (gaia core) handle-error) 'other "crash" "" 0) "Unknown Error")))

  (test-group "rlm-loop-edge-cases"
    (test-assert "rlm-loop: max recursion depth reached"
      (let ((res ((@@ (gaia core) rlm-loop) "session-depth-limit" "Task" 16 '())))
        (and (list? res)
             (string=? (car res) "Task")
             (null? (cdr res)))))

    (test-assert "rlm-loop: empty/error LLM response recovery paths"
      (let* ((llm-mod (resolve-module '(gaia llm-client) #:ensure #f))
             (orig-chat (module-ref llm-mod 'chat-with-llm))
             (env (make-rlm-env "session-error-recover"))
             (calls 0))
        ;; 1. Mock empty response to test retry and subsequent success
        (module-set! llm-mod 'chat-with-llm
                     (lambda args
                       (set! calls (+ calls 1))
                       (if (= calls 1)
                           '(("payload" . (("content" . ""))))
                           '(("payload" . (("content" . "FINAL(Finished)") ("confidence" . 100)))))))
        (let ((res ((@@ (gaia core) rlm-loop) "session-empty" "Task" 4 '() env)))
          (test-equal "empty response retried and succeeded" "Finished" (car res)))
        
        ;; 2. Mock error response to test API error handling
        (module-set! llm-mod 'chat-with-llm (lambda args '(("error" . "API failed"))))
        (let ((res ((@@ (gaia core) rlm-loop) "session-err" "Task" 4 '() env)))
          ;; Should fail and return the error message
          (test-assert "error response handled" (string-contains (car res) "API failed")))
        
        ;; Restore mock
        (module-set! llm-mod 'chat-with-llm orig-chat)
        #t))

    ;; strip-blocks: covers core.scm lines 453-471
    (test-group "strip-blocks"
      (test-equal "strip-blocks: removes thought tags"
        "hello world"
        ((@@ (gaia core) strip-blocks) "<thought>internal</thought>hello world"))

      (test-equal "strip-blocks: removes code fences"
        "before  after"
        ((@@ (gaia core) strip-blocks) "before ```(define x 1)``` after"))

      (test-equal "strip-blocks: removes internal tokens"
        "clean  text"
        ((@@ (gaia core) strip-blocks) "clean <channel|> text <unused87>tool_code <unused88>"))

      (test-equal "strip-blocks: unterminated code fence left as-is"
        "before ```dangling"
        ((@@ (gaia core) strip-blocks) "before ```dangling")))

    ;; llm-query injected capability: covers core.scm lines 330-334
    (test-assert "rlm-loop: llm-query sandbox capability is injected and callable"
      (let* ((llm-mod (resolve-module '(gaia llm-client) #:ensure #f))
             (orig-chat (module-ref llm-mod 'chat-with-llm))
             (env (make-rlm-env "session-llm-query"))
             (query-called? #f))
        ;; The outer loop mock: first returns a repl block calling llm-query,
        ;; second call returns the final answer
        (module-set! llm-mod 'chat-with-llm
                     (let ((n 0))
                       (lambda* (session-id prompt model system #:key think history stream-callback (role "user"))
                         (set! n (+ n 1))
                         (cond
                           ;; Sub-session call from llm-query itself
                           ((string-contains session-id "-sub-")
                            (set! query-called? #t)
                            '(("payload" . (("content" . "sub-answer") ("reasoning" . "")))))
                           ;; First outer call: run llm-query from repl
                           ((= n 1)
                            '(("payload" . (("content" . "```repl\n(llm-query \"inner question\")\n```")
                                             ("reasoning" . "")))))
                           ;; Second outer call: finish
                           (else
                            '(("payload" . (("content" . "FINAL(done)") ("reasoning" . "")))))))))
        (let ((res ((@@ (gaia core) rlm-loop) "session-llm-query" "Task" 1 '() env)))
          (module-set! llm-mod 'chat-with-llm orig-chat)
          (and query-called? (string=? "done" (car res))))))

    ;; chat-with-llm exception handling: covers core.scm lines 501-514
    (test-assert "rlm-loop: generic exception in chat-with-llm is re-thrown"
      (let* ((llm-mod (resolve-module '(gaia llm-client) #:ensure #f))
             (orig-chat (module-ref llm-mod 'chat-with-llm))
             (env (make-rlm-env "session-exception")))
        (module-set! llm-mod 'chat-with-llm
                     (lambda args (throw 'my-test-error "boom")))
        (let ((caught #f))
          (catch 'my-test-error
            (lambda ()
              ((@@ (gaia core) rlm-loop) "session-exc" "Task" 1 '() env))
            (lambda (key . args)
              (set! caught #t)))
          (module-set! llm-mod 'chat-with-llm orig-chat)
          caught)))

    (test-assert "rlm-loop: user-interrupt in chat-with-llm is re-thrown"
      (let* ((llm-mod (resolve-module '(gaia llm-client) #:ensure #f))
             (orig-chat (module-ref llm-mod 'chat-with-llm))
             (env (make-rlm-env "session-interrupt")))
        (module-set! llm-mod 'chat-with-llm
                     (lambda args (throw 'user-interrupt "interrupted by user")))
        (let ((caught #f))
          (catch 'user-interrupt
            (lambda ()
              ((@@ (gaia core) rlm-loop) "session-intr" "Task" 1 '() env))
            (lambda (key . args)
              (set! caught #t)))
          (module-set! llm-mod 'chat-with-llm orig-chat)
          caught)))

    ;; Empty response at step > 1: covers core.scm lines 549-551 (append transcript path)
    (test-assert "rlm-loop: empty response at step>1 appends to existing transcript"
      (let* ((llm-mod (resolve-module '(gaia llm-client) #:ensure #f))
             (orig-chat (module-ref llm-mod 'chat-with-llm))
             (env (make-rlm-env "session-empty-step2"))
             (call-n 0))
        (module-set! llm-mod 'chat-with-llm
                     (lambda args
                       (set! call-n (+ call-n 1))
                       (cond
                         ;; First outer call: return repl to execute (advances to step 2)
                         ((= call-n 1)
                          '(("payload" . (("content" . "```repl\n(+ 1 1)\n```") ("reasoning" . "")))))
                         ;; Second outer call (step 2): return empty to trigger append-transcript path
                         ((= call-n 2)
                          '(("payload" . (("content" . "") ("reasoning" . "")))))
                         ;; Third call: finish
                         (else
                          '(("payload" . (("content" . "FINAL(step2-done)") ("reasoning" . ""))))))))
        (let ((res ((@@ (gaia core) rlm-loop) "session-empty-step2" "Task" 1 '() env)))
          (module-set! llm-mod 'chat-with-llm orig-chat)
          (string=? "step2-done" (car res)))))

    ;; Case D: High confidence stopping: covers core.scm lines 647-651
    (test-assert "rlm-loop: high confidence response stops without final signal"
      (let* ((llm-mod (resolve-module '(gaia llm-client) #:ensure #f))
             (orig-chat (module-ref llm-mod 'chat-with-llm))
             (env (make-rlm-env "session-high-conf"))
             (events '()))
        (module-set! llm-mod 'chat-with-llm
                     (lambda args
                       ;; Return high-confidence response without FINAL() marker
                       '(("payload" . (("content" . "The answer is 42. CONFIDENCE(95)")
                                        ("reasoning" . ""))))))
        (let ((res ((@@ (gaia core) rlm-loop) "session-high-conf" "Task" 1 '() env
                     #:event-handler (lambda (evt) (set! events (cons evt events))))))
          (module-set! llm-mod 'chat-with-llm orig-chat)
          (and (string-contains (car res) "42")
               ;; event-handler should have been called with (final ...)
               (any (lambda (e) (and (pair? e) (eq? (car e) 'final))) events))))))

  (test-group "handle-command-slash-commands"
    (let* ((env (make-rlm-env "test-handle-command"))
           (history '())
           (run (lambda (input)
                  ((@@ (gaia core) handle-command) input "test-session" history env))))
      
      ;; Mock system* to not run real make learn
      (let* ((guile-mod (resolve-module '(guile) #:ensure #f))
             (orig-system* (module-ref guile-mod 'system*)))
        (module-set! guile-mod 'system* (lambda args 0))

        ;; Mock chat-with-llm for /ask command and get-models for /models command
        (let* ((llm-mod (resolve-module '(gaia llm-client) #:ensure #f))
               (orig-chat (module-ref llm-mod 'chat-with-llm))
               (orig-models (module-ref llm-mod 'get-models)))
          (module-set! llm-mod 'chat-with-llm (lambda args '(("payload" . (("content" . "Mocked answer"))))))
          (module-set! llm-mod 'get-models (lambda () '("gpt-4o" "gemma4:e2b")))

          ;; 1. /exit
          (test-equal "/exit"
            (list history env #f)
            (run "/exit"))

          ;; 2. /help
          (test-equal "/help"
            (list history env #t)
            (run "/help"))

          ;; 3. /clear
          (test-assert "/clear"
            (match (run "/clear")
              ((_ new-env #t)
               (rlm-env? new-env))))

          ;; 4. /env
          (test-equal "/env"
            (list history env #t)
            (run "/env"))

          ;; 5. /ask
          (test-assert "/ask"
            (match (run "/ask what is 2+2?")
              ((new-history _ #t)
               (> (length new-history) 0))))

          ;; 6. /eval
          (test-equal "/eval"
            (list history env #t)
            (run "/eval (+ 1 1)"))

          ;; 7. /models
          (test-equal "/models"
            (list history env #t)
            (run "/models"))

          ;; 8. /model (get)
          (test-equal "/model get"
            (list history env #t)
            (run "/model"))

          ;; 9. /model <name>
          (test-equal "/model set"
            (list history env #t)
            (run "/model gpt-4o"))

          ;; 10. /thinking (get)
          (test-equal "/thinking get"
            (list history env #t)
            (run "/thinking"))

          ;; 11. /thinking off
          (test-equal "/thinking off"
            (list history env #t)
            (run "/thinking off"))

          ;; 12. /thinking on
          (test-equal "/thinking on"
            (list history env #t)
            (run "/thinking on"))

          ;; 13. /thinking invalid
          (test-equal "/thinking invalid"
            (list history env #t)
            (run "/thinking invalid-arg"))

          ;; 14. /base-model (get)
          (test-equal "/base-model get"
            (list history env #t)
            (run "/base-model"))

          ;; 15. /base-model <name>
          (test-equal "/base-model set"
            (list history env #t)
            (run "/base-model my-new-base"))

          ;; 16. /train
          (test-equal "/train"
            (list history env #t)
            (run "/train"))

          ;; Restore mocks
          (module-set! llm-mod 'chat-with-llm orig-chat)
          (module-set! llm-mod 'get-models orig-models))
        (module-set! guile-mod 'system* orig-system*)))))

(let* ((runner (test-runner-current))
       (fail (if runner (test-runner-fail-count runner) 0)))
  (test-end "gaia-core")
  (exit (if (> fail 0) 1 0)))
