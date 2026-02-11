(define-module (gaia config)
  #:use-module (ice-9 match)
  #:export (load-config get-config))

(define %default-config
  `((rai-url . "http://localhost:8000")
    (model . "ministral-3:3b")
    (backend . "ollama")
    (framework . "pydantic_ai")
    (system-prompt . #f))) ;; Default system prompt is usually hardcoded in core, but can be overridden

(define *config* (make-parameter %default-config))

(define (get-env-override key)
  "Maps config keys to environment variables and returns value if set."
  (let ((env-var (case key
                   ((rai-url) "RAI_URL")
                   ((model) "GAIA_MODEL")
                   ((backend) "RAI_BACKEND")
                   ((framework) "RAI_FRAMEWORK")
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
