(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (srfi srfi-64)
             (srfi srfi-11)
             (ice-9 receive)
             (gaia llm-client)
             (gaia config))

;; Reload gaia llm-client to purge any mocks left by previous test files running in the same process
(let ((llm-mod (resolve-module '(gaia llm-client) #:ensure #f))
      (abs-path (canonicalize-path (string-append (dirname (current-filename)) "/../src/gaia/llm-client.scm"))))
  (when llm-mod
    (save-module-excursion
      (lambda ()
        (set-current-module llm-mod)
        (load abs-path)))))

;; Mock the (web client) and (web response) modules
(define captured-request-body #f)

(let ((client-mod (resolve-module '(web client) #:ensure #f))
      (resp-mod (resolve-module '(web response) #:ensure #f)))

  ;; Mock http-post
  (module-set! client-mod 'http-post
               (lambda* (url #:key body headers)
                 (set! captured-request-body body)
                 (cond
                  ((string-contains url "/v1/chat/completions")
                   (values 'mock-hdr "{\"choices\": [{\"message\": {\"content\": \"Sync Hello\", \"reasoning_content\": \"Thinking hard\"}}], \"usage\": {\"prompt_tokens\": 8, \"completion_tokens\": 2, \"total_tokens\": 10}}"))
                  (else
                   (values 'mock-hdr "{}")))))

  ;; Mock http-get
  (module-set! client-mod 'http-get
               (lambda (url)
                 (cond
                  ((string-contains url "/v1/models")
                   (values 'mock-hdr "{\"data\": [{\"id\": \"gemma4:e2b\"}, {\"id\": \"gpt-4o\"}]}"))
                  (else
                   (values 'mock-hdr "{}")))))

  ;; Mock open-socket-for-uri
  (module-set! client-mod 'open-socket-for-uri
               (lambda (uri)
                 (car (pipe))))

  ;; Mock http-request
  (module-set! client-mod 'http-request
               (lambda* (url #:key method body headers streaming? port)
                 (let ((build-resp (module-ref resp-mod 'build-response)))
                   (cond
                    ((string-contains url "error")
                     (values (build-resp #:code 500) (open-input-string "Error message from server")))
                    (else
                     (values (build-resp #:code 200)
                             (open-input-string
                              "data: {\"choices\": [{\"delta\": {\"content\": \"Hello\", \"reasoning_content\": \"Thinking\"}}]}\n\ndata: {\"choices\": [{\"delta\": {\"content\": \" world\", \"reasoning_content\": \"\"}}]}\n\ndata: [DONE]\n"))))))))

(test-begin "gaia-llm-client")

;; 1. Test get-models
(test-equal "get-models returns ids list"
  '("gemma4:e2b" "gpt-4o")
  (get-models))

;; 2. Test chat-with-llm synchronous non-streaming
(test-assert "chat-with-llm synchronous preserves token usage"
  (let* ((response (chat-with-llm "session-sync" "Hello sync" "gpt-4o" "System prompt"))
         (payload (assoc-ref response "payload"))
         (usage (assoc-ref response "usage")))
    (and (equal? (assoc-ref payload "content") "Sync Hello")
         (equal? (assoc-ref payload "reasoning") "Thinking hard")
         (= (assoc-ref usage "prompt_tokens") 8)
         (= (assoc-ref usage "completion_tokens") 2)
         (= (assoc-ref usage "total_tokens") 10))))

(test-assert "chat-with-llm sends a bounded max_tokens value"
  (begin
    (set! captured-request-body #f)
    (chat-with-llm "session-bounded" "Hello" "gpt-4o" "System prompt"
                   #:max-output-tokens 321)
    (and (string? captured-request-body)
         (string-contains captured-request-body "\"max_tokens\":321"))))

(test-error "chat-with-llm rejects a non-positive output token limit"
  (chat-with-llm "session-unbounded" "Hello" "gpt-4o" "System prompt"
                 #:max-output-tokens 0))

(test-assert "chat-with-llm synchronous fails with a bounded timeout"
  (let* ((web-client-module (resolve-module '(web client)))
         (original-http-post (module-ref web-client-module 'http-post)))
    (dynamic-wind
      (lambda ()
        (module-set! web-client-module 'http-post
                     (lambda* (url #:key body headers)
                       (usleep 250000)
                       (values 'mock-hdr "{}"))))
      (lambda ()
        (catch 'llm-timeout
          (lambda ()
            (chat-with-llm "session-timeout" "Wait" "qwen3:4b"
                           "System prompt" #:timeout-seconds 0.02)
            #f)
          (lambda (key seconds)
            (and (eq? key 'llm-timeout) (= seconds 0.02)))))
      (lambda ()
        (module-set! web-client-module 'http-post original-http-post)))))

;; 3. Test chat-with-llm streaming path
(test-assert "chat-with-llm streaming"
  (let* ((tokens '())
         (thoughts '())
         (callback (lambda (evt)
                     (case (car evt)
                       ((token) (set! tokens (cons (cadr evt) tokens)))
                       ((thought) (set! thoughts (cons (cadr evt) thoughts))))))
         (res (chat-with-llm "session-stream" "Hello stream" "gemma4:e2b" "System prompt"
                             #:stream-callback callback)))
    (and (equal? res '(("payload" . (("content" . "Hello world") ("reasoning" . "Thinking")))))
         (equal? (reverse tokens) '("Hello" " world"))
         (equal? (reverse thoughts) '("Thinking")))))

;; 4. Test chat-with-llm streaming error path
(test-assert "chat-with-llm streaming error"
  (let* ((old-url (get-config 'llm-url))
         (dummy (set-config! 'llm-url "http://localhost:4000/error"))
         (res (chat-with-llm "session-error" "Hello error" "gemma-error" "System prompt"
                             #:stream-callback (lambda (_) #t)))
         (dummy2 (set-config! 'llm-url old-url)))
    (and (list? res)
         (string-contains (assoc-ref res "error") "Error message from server"))))

;; 5. Test model-supports-thinking?
(test-assert "model-supports-thinking?"
  (and ((@@ (gaia llm-client) model-supports-thinking?) "gemma4")
       ((@@ (gaia llm-client) model-supports-thinking?) "r1-reasoning")
       ((@@ (gaia llm-client) model-supports-thinking?) "qwen3:4b")
       ((@@ (gaia llm-client) model-supports-thinking?) "gpt-oss:20b")
       (not ((@@ (gaia llm-client) model-supports-thinking?) "gpt-4o"))))

(test-equal "qwen3 thinking can be disabled through LiteLLM passthrough"
  '(("think" . #f)
    ("allowed_openai_params" . #("think")))
  ((@@ (gaia llm-client) get-thinking-fields) "qwen3:4b" #f))

(test-equal "qwen3 thinking level is preserved"
  '(("think" . "high")
    ("allowed_openai_params" . #("think")))
  ((@@ (gaia llm-client) get-thinking-fields) "qwen3:4b" "high"))

(test-assert "thinking boolean aliases are normalized"
  (and (eq? (normalize-thinking-setting "true") #t)
       (eq? (normalize-thinking-setting "false") #f)
       (eq? (normalize-thinking-setting "none") #f)
       (equal? (normalize-thinking-setting "HIGH") "high")
       (eq? (normalize-thinking-setting "turbo") 'invalid)))

;; 6. Test stream filter process-buffer! edge cases
(test-assert "make-stream-filter process-buffer!"
  (let* ((output '())
         (cb (lambda (evt) (set! output (cons evt output))))
         (filter (make-stream-filter cb)))
    (filter '(token "Hello <think>secret</think>world"))
    (filter '(flush))
    (equal? (reverse output)
            '((token "Hello ")
              (thought "secret")
              (token "world")))))

(test-end "gaia-llm-client")
