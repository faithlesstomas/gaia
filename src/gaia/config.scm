(define-module (gaia config)
  #:use-module (ice-9 match)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (load-config get-config set-config! gaia-version *workspace-path*
            normalize-thinking-setting thinking-setting->string))

(define *workspace-path* (make-parameter #f))

(define gaia-version
  (let* ((port (open-input-pipe "git describe --tags --always --dirty 2>/dev/null"))
         (ver (read-line port)))
    (close-pipe port)
    (if (or (eof-object? ver) (string-null? ver))
        "X.Y.Z" ;; No version info available
        ver)))

(define %default-config
  `((llm-url . "http://localhost:4000")
    (llm-timeout-seconds . 300)
    (llm-max-output-tokens . 2048)
    (model . "gemma4:e2b")
    (base-model . "gemma4:e2b")
    (thinking . #t)
    (system-prompt . #f)
    (conversation-system-prompt . #f)
    (state-injection . #f)
    (wisp-mode . #f)
    (allow-sandbox-fallback . #f))) ;; Default system prompt is usually hardcoded in core, but can be overridden

(define *config* (make-parameter %default-config))

(define (set-config! key value)
  "Updates the configuration value for a specific key."
  (let ((current (*config*)))
    (*config* (acons key value (alist-delete key current)))))

(define (normalize-thinking-setting value)
  "Normalize a thinking setting, or return the symbol 'invalid.
The normalized value is #t, #f, or one of the Ollama effort-level strings."
  (cond
   ((boolean? value) value)
   ((string? value)
    (let ((setting (string-downcase (string-trim-both value))))
      (cond
       ((member setting '("on" "true" "1")) #t)
       ((member setting '("off" "false" "0" "none")) #f)
       ((member setting '("low" "medium" "high" "max")) setting)
       (else 'invalid))))
   (else 'invalid)))

(define (thinking-setting->string value)
  "Return the CLI/API spelling of a normalized thinking setting."
  (cond
   ((eq? value #t) "on")
   ((eq? value #f) "off")
   ((string? value) value)
   (else "invalid")))

(define (get-env-override key)
  "Maps config keys to environment variables and returns value if set."
  (let ((env-val (let ((env-var (case key
                                  ((llm-url) "GAIA_LLM_URL")
                                  ((llm-timeout-seconds)
                                   "GAIA_LLM_TIMEOUT_SECONDS")
                                  ((llm-max-output-tokens)
                                   "GAIA_LLM_MAX_OUTPUT_TOKENS")
                                  ((model) "GAIA_MODEL")
                                  ((base-model) "GAIA_BASE_MODEL")
                                  ((system-prompt) "GAIA_SYSTEM_PROMPT")
                                  ((conversation-system-prompt)
                                   "GAIA_CONVERSATION_SYSTEM_PROMPT")
                                  ((state-injection) "GAIA_STATE_INJECTION")
                                  ((wisp-mode) "GAIA_WISP_MODE")
                                  ((allow-sandbox-fallback) "GAIA_ALLOW_SANDBOX_FALLBACK")
                                  (else #f))))
                   (and env-var (getenv env-var)))))
    (cond
     ((and env-val
           (member key '(allow-sandbox-fallback state-injection wisp-mode)))
      (or (string=? env-val "1")
          (string-ci=? env-val "true")
          (string-ci=? env-val "yes")))
     ((and env-val
           (member key '(llm-timeout-seconds llm-max-output-tokens)))
      (let ((number (string->number env-val)))
        (and (number? number) (integer? number) (> number 0) number)))
     (else env-val))))

(define (load-config)
  "Loads configuration from defaults and environment variables."
  (let ((new-config (map (lambda (pair)
                           (let* ((key (car pair))
                                  (default-val (cdr pair))
                                  (env-val (get-env-override key)))
                             (cons key (or env-val default-val))))
                         %default-config)))
    (*config* new-config)
    new-config))

(define (get-config key)
  "Returns the value for the given config key."
  (assoc-ref (*config*) key))
