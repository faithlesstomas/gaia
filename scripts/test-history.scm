(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (gaia core)
             (gaia llm-client)
             (gaia config)
             (gaia rlm-env)
             (srfi srfi-1)
             (srfi srfi-64)
             (ice-9 match))

(load-config)

(test-begin "gaia-history")

;; --- Test 1: Meta-komenda /clear ---
(test-group "meta-clear"
  (let* ((old-history '((("role" . "user") ("content" . "hello"))))
         (result ((@@ (gaia core) handle-command) "/clear" "test-session" old-history (make-rlm-env))))
    (test-equal "history is empty after /clear"
      '()
      (car result))))

;; --- Test 2: Meta-komenda /ask ---
(test-group "meta-ask"
  ;; Mockujemy chat-with-llm w module źródłowym
  (module-define! (resolve-module '(gaia llm-client)) 'chat-with-llm 
    (lambda* (session-id input model prompt #:key (think #f) (history '()))
      `(("payload" . (("content" . "AI Response"))))))
  
  (let* ((initial-history '())
         (result ((@@ (gaia core) handle-command) "/ask test" "test-session" initial-history (make-rlm-env)))
         (new-history (car result)))
    (test-equal "history length after /ask" 2 (length new-history))
    (test-equal "assistant response in history" "AI Response" (assoc-ref (last new-history) "content"))))

;; --- Test 3: Standardowa pętla RLM i aktualizacja historii ---
(test-group "rlm-loop-history"
  ;; Nadpisujemy chat-with-llm, aby rlm-loop zwrócił przewidywalny wynik przez FINAL
  (module-define! (resolve-module '(gaia llm-client)) 'chat-with-llm 
    (lambda* (session-id input model prompt #:key (think #f) (history '()))
      `(("payload" . (("content" . "The result is FINAL(Verified Answer)"))))))
  
  (let* ((initial-history '())
         (result ((@@ (gaia core) handle-command) "run task" "test-session" initial-history (make-rlm-env)))
         (new-history (car result)))
    (test-equal "history updated after RLM loop" 2 (length new-history))
    ;; Sprawdzamy czy "Verified Answer" trafiło do historii
    (test-equal "captured answer matches mock" "Verified Answer" (assoc-ref (last new-history) "content"))))

;; --- Test 4: Propagacja historii do rlm-loop-inner ---
(test-group "rlm-loop-history-propagation"
  (module-define! (resolve-module '(gaia llm-client)) 'chat-with-llm 
    (lambda* (session-id input model prompt #:key (think #f) (history '()))
      (if (and (list? history) (not (null? history)))
          `(("payload" . (("content" . "FOUND_HISTORY"))))
          `(("payload" . (("content" . "NO_HISTORY")))))))
  
  (let* ((test-history '((("role" . "user") ("content" . "context"))))
         (rlm-inner (@@ (gaia core) rlm-loop-inner))
         (env (make-rlm-env))
         (answer (rlm-inner "test-session" "task" 0 env test-history 1 '())))
    (test-assert "history reached chat-with-llm via rlm-loop-inner"
      (string-contains answer "FOUND_HISTORY"))))

;; --- Test 5: Meta-komenda /env ---
(test-group "meta-env"
  (let* ((initial-history '())
         (env (make-rlm-env)))
    (rlm-eval! env "(define my-test-var 42)")
    ;; We capture stdout to ensure `/env` actually prints my-test-var
    (let* ((output-port (open-output-string))
           (result (with-output-to-port output-port
                     (lambda ()
                       ((@@ (gaia core) handle-command) "/env" "test-session" initial-history env))))
           (output (get-output-string output-port))
           (new-history (car result))
           (continue? (caddr result)))
      (test-assert "history remains unchanged after /env" (null? new-history))
      (test-assert "session continues after /env" continue?)
      (test-assert "output contains defined variable"
        (if (string-contains output "my-test-var = 42") #t #f)))))

(test-end "gaia-history")
