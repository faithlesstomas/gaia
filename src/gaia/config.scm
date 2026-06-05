(define-module (gaia config)
  #:use-module (ice-9 match)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (srfi srfi-1)
  #:export (load-config get-config set-config! gaia-version))

(define gaia-version
  (let* ((port (open-input-pipe "git describe --tags --always --dirty 2>/dev/null"))
         (ver (read-line port)))
    (close-pipe port)
    (if (or (eof-object? ver) (string-null? ver))
        "X.Y.Z" ;; No version info available
        ver)))

(define %default-config
  `((llm-url . "http://localhost:4000")
    (model . "gemma4:e2b")
    (base-model . "gemma4:e2b")
    (thinking . #t)
    (system-prompt . #f))) ;; Default system prompt is usually hardcoded in core, but can be overridden

(define *config* (make-parameter %default-config))

(define (set-config! key value)
  "Updates the configuration value for a specific key."
  (let ((current (*config*)))
    (*config* (acons key value (alist-delete key current)))))

(define (get-env-override key)
  "Maps config keys to environment variables and returns value if set."
  (let ((env-var (case key
                   ((llm-url) "GAIA_LLM_URL")
                   ((model) "GAIA_MODEL")
                   ((base-model) "GAIA_BASE_MODEL")
                   ((system-prompt) "GAIA_SYSTEM_PROMPT")
                   (else #f))))
    (and env-var (getenv env-var))))

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
