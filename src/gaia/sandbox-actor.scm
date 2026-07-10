(define-module (gaia sandbox-actor)
  #:use-module (ice-9 match)
  #:use-module (goblins)
  #:use-module (goblins actor-lib methods)
  #:use-module (gaia sandbox)
  #:use-module (gaia executor)
  #:use-module (gaia rlm-env)
  #:use-module (gaia config)
  #:use-module (gaia core)
  #:use-module (gaia llm-client)
  #:use-module (gaia utils)
  #:export (^repl-sandbox
            ^repl-sandbox-from-env))

(define (replay-history env history)
  (for-each (lambda (turn)
              (let ((role (or (assoc-ref turn 'role) (assoc-ref turn "role")))
                    (trajectory (or (assoc-ref turn 'trajectory) (assoc-ref turn "trajectory"))))
                (if trajectory
                    (for-each (lambda (step)
                                (let ((step-role (or (assoc-ref step 'role) (assoc-ref step "role")))
                                      (step-content (or (assoc-ref step 'content) (assoc-ref step "content"))))
                                  (when (and step-role (string=? (format #f "~a" step-role) "assistant") step-content)
                                    (let ((code (extract-code step-content)))
                                      (when code
                                        (rlm-eval! env code #:permission-handler (lambda (_) #t)))))))
                              (if (vector? trajectory) (vector->list trajectory) trajectory))
                    (let ((content (or (assoc-ref turn 'content) (assoc-ref turn "content"))))
                      (when (and role content)
                        (let ((role-str (format #f "~a" role)))
                          (cond
                           ((string=? role-str "assistant")
                            (let ((code (extract-code content)))
                              (when code
                                (rlm-eval! env code #:permission-handler (lambda (_) #t)))))
                           ((string=? role-str "user-repl")
                            (let ((code (extract-code content)))
                              (when code
                                (rlm-eval! env code #:permission-handler (lambda (_) #t))))))))))))
            history))

;; Sandbox Actor
(define-actor (^repl-sandbox bcom session-id event-handler permission-handler history)
  (let ((env (make-rlm-env session-id event-handler permission-handler)))
    (rlm-inject! env 'llm-query
      (lambda (prompt)
        (let* ((sub-session (string-append session-id "-sub-" (number->string (random 1000000000))))
               (response (chat-with-llm sub-session prompt (get-config 'model) (or (get-config 'system-prompt) SYSTEM_PROMPT) #:history '()))
               (payload (assoc-ref response "payload")))
          (if payload
              (assoc-ref payload "content")
              "Error: No response from sub-LLM"))))
    (when (and history (not (null? history)))
      (replay-history env history))
    (methods
     [(eval code)
      (rlm-execute env code)]
     [(definitions)
      (rlm-env-user-bindings env)]
     [(save-checkpoint)
      (let ((sb (rlm-env-sandbox env)))
        (backup-module (sandbox-module sb) (sandbox-initial-symbols sb)))]
     [(restore-checkpoint backup)
      (let ((sb (rlm-env-sandbox env)))
        (restore-module! (sandbox-module sb) (sandbox-initial-symbols sb) backup)
        'ok)]
     [(fork)
      (let* ((sb (rlm-env-sandbox env))
             (cloned-sb (fork-sandbox sb))
             (cloned-env (%make-rlm-env cloned-sb (rlm-env-history env) (rlm-env-injected-bindings env))))
        (spawn ^repl-sandbox-from-env cloned-env) ) ] ) ) )

(define-actor (^repl-sandbox-from-env bcom env)
  (methods
   [(eval code)
    (rlm-execute env code)]
   [(definitions)
    (rlm-env-user-bindings env)]
   [(save-checkpoint)
    (let ((sb (rlm-env-sandbox env)))
      (backup-module (sandbox-module sb) (sandbox-initial-symbols sb)))]
   [(restore-checkpoint backup)
    (let ((sb (rlm-env-sandbox env)))
      (restore-module! (sandbox-module sb) (sandbox-initial-symbols sb) backup)
      'ok)]
   [(fork)
    (let* ((sb (rlm-env-sandbox env))
           (cloned-sb (fork-sandbox sb))
           (cloned-env (%make-rlm-env cloned-sb (rlm-env-history env) (rlm-env-injected-bindings env))))
      (spawn ^repl-sandbox-from-env cloned-env) ) ] ) )
