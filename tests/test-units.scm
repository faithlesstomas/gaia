(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (gaia executor)
             (gaia core)
             (gaia utils)
             (gaia rlm-env)
             (srfi srfi-64))

(test-begin "gaia-core")

(test-group "utils"
  (test-equal "json conversion"
    "{\"key\":\"value\"}"
    (scm->json '(("key" . "value")))))

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

(test-group "core"
  (test-group "extractors"
    (test-equal "extract-code: repl block"
      "(+ 1 2)"
      (extract-code "```repl\n(+ 1 2)\n```"))
    
    (test-equal "extract-code: scheme block"
      "(* 3 4)"
      (extract-code "```scheme\n(* 3 4)\n```"))
    
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
      (clean-assistant-content "```repl\n(+ 1 2)\n``` FINAL(42) CONFIDENCE(100)")))

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

  (test-group "error-handling"
    (test-assert "handle-error: syntax"
      (string-contains ((@@ (gaia core) handle-error) 'syntax "unmatched parens" "(+ 1" 0) "Syntax Error"))
    (test-assert "handle-error: permission"
      (string-contains ((@@ (gaia core) handle-error) 'permission "Violation" "(system)" 0) "Security Violation"))
    (test-assert "handle-error: runtime"
      (string-contains ((@@ (gaia core) handle-error) 'runtime "failure" "(+)" 0) "Runtime Error"))
    (test-assert "handle-error: unknown"
      (string-contains ((@@ (gaia core) handle-error) 'other "crash" "" 0) "Unknown Error"))))

(let* ((runner (test-runner-current))
       (fail (if runner (test-runner-fail-count runner) 0)))
  (test-end "gaia-core")
  (exit (if (> fail 0) 1 0)))
