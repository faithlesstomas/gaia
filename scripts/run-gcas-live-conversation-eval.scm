(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (ice-9 format)
             (srfi srfi-1)
             (srfi srfi-13)
             (gaia com)
             (gaia config)
             (gaia cognitive-bus)
             (gaia cognitive-memory)
             (gaia cognitive-session)
             (gaia cognitive-state)
             (gaia cognitive-trace)
             (gaia conversation-processors)
             (gaia core)
             (gaia gcas-evaluation)
             (gaia llm-client)
             (gaia utils))

(define (env-boolean name fallback)
  (let ((value (getenv name)))
    (if value
        (and (member (string-downcase (string-trim-both value))
                     '("1" "true" "yes" "on"))
             #t)
        fallback)))

(define (env-positive-number name fallback)
  (let* ((value (getenv name))
         (parsed (and value (string->number value))))
    (if (and (number? parsed) (> parsed 0)) parsed fallback)))

(define (env-nonnegative-integer name fallback)
  (let* ((value (getenv name))
         (parsed (and value (string->number value))))
    (if (and (integer? parsed) (>= parsed 0)) parsed fallback)))

(define (env-single-model)
  (let* ((raw (or (getenv "GAIA_EVAL_MODELS") (get-config 'model)))
         (models
          (filter (lambda (item) (not (string-null? item)))
                  (map string-trim-both (string-split raw #\,)))))
    (if (= (length models) 1)
        (car models)
        (error "Live conversation evaluation permits exactly one model"
               models))))

(load-config)

(define model (env-single-model))
(define model-parameters-b
  (env-positive-number "GAIA_EVAL_MODEL_PARAMETERS_B" #f))
(define max-model-parameters-b
  (env-positive-number "GAIA_EVAL_MAX_MODEL_PARAMETERS_B" 4.0))
(define resource-approved?
  (env-boolean "GAIA_EVAL_RESOURCE_APPROVED" #f))
(define thinking? (env-boolean "GAIA_EVAL_THINKING" #f))
(define verbosity (env-nonnegative-integer "GAIA_EVAL_VERBOSE" 1))
(define output-path (getenv "GAIA_CONVERSATION_EVAL_OUTPUT"))
(define session-key
  (format #f "gcas-live-conversation-~a" (getpid)))
(define memory-path
  (format #f "/tmp/~a-memory.scm" session-key))
(define state-path
  (format #f "/tmp/~a-state.scm" session-key))
(define recall-token "GAIA-MVP-7319")

(when (> verbosity 3)
  (error "GAIA_EVAL_VERBOSE must be an integer from 0 through 3" verbosity))

(validate-live-resource-policy
 (list model) resource-approved? model-parameters-b
 #:max-model-parameters-b max-model-parameters-b)

(for-each (lambda (path)
            (when (file-exists? path) (delete-file path)))
          (list memory-path state-path))

(define (timestamp)
  (strftime "%Y-%m-%dT%H:%M:%S%z" (localtime (current-time))))

(define (log level kind message)
  (when (>= verbosity level)
    (format #t "[~a] [~a] ~a\n" (timestamp) kind message)
    (force-output)))

(define (make-live-session restore?)
  (make-cognitive-session
   #:memory-path memory-path #:state-path state-path #:restore? restore?
   #:trace-sink
   (and (>= verbosity 2)
        (make-cognitive-trace-sink
         session-key (lambda (message) (log 2 "EVENT" message))))
   #:diagnostic-sink
   (and (>= verbosity 3)
        (lambda (session type payload)
          (log 3 "PROCESSOR"
               (format #f "diagnostic=~a details=~s" type payload))))))

(define (run-turn session index utterance)
  (let ((prompt #f)
        (response #f)
        (outcome #f)
        (started (get-internal-real-time)))
    (log 1 "TURN" (format #f "~a/2 START model=~a" index model))
    (start-conversation-process!
     session utterance
     #:generate
     (lambda (context succeed fail)
       (set! prompt context)
       (log 3 "PROMPT" context)
       (log 1 "LLM"
            (format #f "START turn=~a timeout=~as endpoint=~a"
                    index (get-config 'llm-timeout-seconds)
                    (get-config 'llm-url)))
       (catch #t
         (lambda ()
           ;; The protocol history is deliberately empty. Continuity can enter
           ;; only through CONTEXT reconstructed from typed Cognitive Memory.
           (let* ((llm-response
                   (chat-with-llm
                    session-key context model
                    (get-gcas-conversation-system-prompt)
                    #:think thinking? #:history '()))
                  (payload (assoc-ref llm-response "payload"))
                  (error-text (assoc-ref llm-response "error")))
             (if (and payload (not error-text))
                 (begin
                   (log 1 "LLM" (format #f "END turn=~a" index))
                   (log 3 "RESPONSE" (assoc-ref payload "content"))
                   (succeed (assoc-ref payload "content")))
                 (fail (or error-text
                           (format #f "Invalid LLM response: ~s"
                                   llm-response))))))
         (lambda (key . args)
           (fail (format #f "~a ~s" key args)))))
     #:on-finished
     (lambda (terminal final-text hypothesis-text)
       (set! outcome terminal)
       (set! response final-text)))
    (let ((latency-ms
           (* 1000.0
              (/ (- (get-internal-real-time) started)
                 internal-time-units-per-second))))
      (log 1 "TURN"
           (format #f "~a/2 END outcome=~a latency=~,1fms"
                   index outcome latency-ms))
      `((index . ,index)
        (utterance . ,utterance)
        (outcome . ,outcome)
        (prompt . ,prompt)
        (response . ,response)
        (latency-ms . ,latency-ms)))))

(define first-session (make-live-session #f))
(define first
  (run-turn
   first-session 1
   (string-append
    "Zapamiętaj identyfikator tej rozmowy: " recall-token
    ". Odpowiedz krótko, że go zapamiętałeś.")))

;; Reconstruct the next turn from the durable graph in a fresh session object.
(define restored-session (make-live-session #t))
(define second
  (run-turn
   restored-session 2
   "Jaki identyfikator rozmowy podałem wcześniej? Odpowiedz samym identyfikatorem."))

(define second-prompt (or (assoc-ref second 'prompt) ""))
(define second-response (or (assoc-ref second 'response) ""))
(define assistant-turns
  (filter
   (lambda (co)
     (eq? (assoc-ref (co-relations co) 'conversation-speaker) 'ASSISTANT))
   (memory-objects (session-memory restored-session))))
(define delivery-claims
  (filter
   (lambda (co)
     (and (fact? co)
          (eq? (assoc-ref (co-relations co) 'verification-scope)
               'DELIVERY_ONLY)))
   (state-objects (session-state restored-session))))
(define checks
  `((both-turns-completed
     . ,(and (eq? (assoc-ref first 'outcome) 'COMPLETED)
             (eq? (assoc-ref second 'outcome) 'COMPLETED)))
    (recall-token-in-projection
     . ,(and (string-contains second-prompt recall-token) #t))
    (recall-token-in-response
     . ,(and (string-contains (string-upcase second-response) recall-token) #t))
    (bounded-projection . ,(<= (string-length second-prompt) 6000))
    (not-transcript-replay
     . ,(and (string-contains second-prompt "not a transcript replay") #t))
    (assistant-content-unverified
     . ,(and (= (length assistant-turns) 2)
             (every (lambda (co)
                      (and (eq? (co-type co) 'hypothesis)
                           (eq? (co-epistemic-status co) 'HYPOTHESIS)
                           (eq? (co-verification-status co) 'UNVERIFIED)))
                    assistant-turns)))
    (delivery-only-claims . ,(= (length delivery-claims) 2))
    (protocol-history-size . 0)))
(define passed?
  (every (lambda (check)
           (or (eq? (car check) 'protocol-history-size)
               (cdr check)))
         checks))

(format #t "LIVE-CONVERSATION model=~a status=~a recall=~a context-chars=~a history=0 timeout=~as\n"
        model (if passed? "PASS" "FAIL")
        (assoc-ref checks 'recall-token-in-response)
        (string-length second-prompt)
        (get-config 'llm-timeout-seconds))

(when (and output-path (not (string-null? (string-trim-both output-path))))
  (write-json-file
   output-path
   `(("schema_version" . 1)
     ("evaluation_contract" . "gcas-live-conversation-v1")
     ("created_at" . ,(timestamp))
     ("endpoint" . ,(get-config 'llm-url))
     ("model" . ,model)
     ("model_parameters_b" . ,model-parameters-b)
     ("max_model_parameters_b" . ,max-model-parameters-b)
     ("operator_approved" . ,resource-approved?)
     ("thinking" . ,thinking?)
     ("timeout_seconds" . ,(get-config 'llm-timeout-seconds))
     ("passed" . ,passed?)
     ("checks" . ,(map (lambda (check)
                          (cons (symbol->string (car check)) (cdr check)))
                        checks))
     ("first_outcome" . ,(symbol->string (assoc-ref first 'outcome)))
     ("second_outcome" . ,(symbol->string (assoc-ref second 'outcome)))
     ("second_context_chars" . ,(string-length second-prompt))
     ("second_response" . ,second-response)))
  (format #t "Wrote conversation report to ~a\n" output-path))

(for-each (lambda (path)
            (when (file-exists? path) (delete-file path)))
          (list memory-path state-path))

(exit (if passed? 0 1))
