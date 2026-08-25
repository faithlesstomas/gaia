(define-module (gaia ncsi)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (ice-9 match)
  #:use-module (gaia com)
  #:export (NCSI-SCHEMA-VERSION
            <ncsi-concept>
            make-ncsi-concept
            ncsi-concept?
            concept-token-id
            concept-display-text
            concept-score
            concept->alist
            alist->concept

            <ncsi-neural-observation>
            make-ncsi-neural-observation
            ncsi-neural-observation?
            obs-schema-version
            obs-request-id
            obs-forward-pass-id
            obs-model-id
            obs-model-revision
            obs-tokenizer-revision
            obs-lens-id
            obs-lens-revision
            obs-layer
            obs-position
            obs-concepts
            obs-readout-method
            obs-parameters
            obs-reconstruction-error
            obs-timestamp
            observation->alist
            alist->observation
            observation->cognitive-object

            <ncsi-event>
            make-ncsi-event
            ncsi-event?
            ncsi-event-type
            ncsi-event-request-id
            ncsi-event-payload
            ncsi-event-timestamp

            ;; Event constructors
            make-ncsi-generation-started
            make-ncsi-token-delta
            make-ncsi-neural-state-observed
            make-ncsi-generation-completed
            make-ncsi-generation-failed

            ;; Parsers and serializers
            parse-ncsi-event
            ncsi-event->alist
            validate-ncsi-event))

(define NCSI-SCHEMA-VERSION "gcas.ncsi.v1")
(define NCSI-MAX-CONCEPTS 64)
(define NCSI-MAX-DISPLAY-TEXT-LENGTH 512)
(define NCSI-MAX-PARAMETERS 32)

;; -----------------------------------------------------------------------------
;; 1. NCSI Concept
;; -----------------------------------------------------------------------------
(define-record-type <ncsi-concept>
  (%make-concept token-id display-text score)
  ncsi-concept?
  (token-id concept-token-id)
  (display-text concept-display-text)
  (score concept-score))

(define (non-empty-string? value)
  (and (string? value) (> (string-length value) 0)))

;; Wire messages may originate as JSON (string keys and event names) or as
;; Scheme alists (symbol keys).  Normalize at this boundary rather than making
;; either transport representation a hidden requirement for sidecar clients.
(define (wire-ref alist key)
  (let ((entry (or (assoc key alist)
                   (assoc (symbol->string key) alist))))
    (and entry (cdr entry))))

(define (wire-has-key? alist key)
  (or (assoc key alist) (assoc (symbol->string key) alist)))

(define (wire-event-type value)
  (if (string? value) (string->symbol value) value))

(define (wire-list value)
  (if (vector? value) (vector->list value) value))

(define (non-negative-integer? value)
  (and (integer? value) (>= value 0)))

(define (bounded-score? value)
  (and (number? value) (<= 0.0 value 1.0)))

(define (token-span? value)
  (let ((value (wire-list value)))
    (and (list? value)
       (= (length value) 2)
       (every non-negative-integer? value)
       (<= (car value) (cadr value)))))

(define (valid-position? value)
  (or (non-negative-integer? value) (token-span? value)))

(define (valid-parameter-value? value)
  (or (string? value) (number? value) (boolean? value) (null? value)))

(define (valid-parameters? value)
  (let ((value (wire-list value)))
    (and (list? value)
       (<= (length value) NCSI-MAX-PARAMETERS)
       (every (lambda (entry)
                (and (pair? entry)
                     (or (symbol? (car entry)) (string? (car entry)))
                     (valid-parameter-value? (cdr entry))))
              value))))

(define* (make-ncsi-concept token-id display-text score)
  (unless (or (integer? token-id) (string? token-id))
    (error "Concept token-id must be an integer or string" token-id))
  (unless (and (string? display-text)
               (<= (string-length display-text) NCSI-MAX-DISPLAY-TEXT-LENGTH))
    (error "Concept display-text must be a bounded string" display-text))
  (unless (bounded-score? score)
    (error "Concept score must be a number in [0, 1]" score))
  (%make-concept token-id display-text score))

(define (concept->alist concept)
  `((token-id . ,(concept-token-id concept))
    (display-text . ,(concept-display-text concept))
    (score . ,(concept-score concept))))

(define (alist->concept alist)
  (let ((token-id (wire-ref alist 'token-id))
        (display-text (wire-ref alist 'display-text))
        (score (wire-ref alist 'score)))
    (unless (and token-id display-text score)
      (error "Invalid concept alist: missing required fields" alist))
    (make-ncsi-concept token-id display-text score)))

;; -----------------------------------------------------------------------------
;; 2. NCSI Neural Observation
;; -----------------------------------------------------------------------------
(define-record-type <ncsi-neural-observation>
  (%make-neural-observation
   schema-version
   request-id
   forward-pass-id
   model-id
   model-revision
   tokenizer-revision
   lens-id
   lens-revision
   layer
   position
   concepts
   readout-method
   parameters
   reconstruction-error
   timestamp)
  ncsi-neural-observation?
  (schema-version obs-schema-version)
  (request-id obs-request-id)
  (forward-pass-id obs-forward-pass-id)
  (model-id obs-model-id)
  (model-revision obs-model-revision)
  (tokenizer-revision obs-tokenizer-revision)
  (lens-id obs-lens-id)
  (lens-revision obs-lens-revision)
  (layer obs-layer)
  (position obs-position)
  (concepts obs-concepts)
  (readout-method obs-readout-method)
  (parameters obs-parameters)
  (reconstruction-error obs-reconstruction-error)
  (timestamp obs-timestamp))

(define* (make-ncsi-neural-observation
          #:key
          (schema-version NCSI-SCHEMA-VERSION)
          request-id
          forward-pass-id
          model-id
          model-revision
          tokenizer-revision
          lens-id
          lens-revision
          layer
          position
          (concepts '())
          (readout-method "jlens-sparse")
          (parameters '())
          (reconstruction-error 0.0)
          (timestamp #f))
  (unless (equal? schema-version NCSI-SCHEMA-VERSION)
    (error "Unsupported NCSI schema version" schema-version))
  (unless (non-empty-string? request-id)
    (error "request-id must be a non-empty string" request-id))
  (unless (non-empty-string? forward-pass-id)
    (error "forward-pass-id must be a non-empty string" forward-pass-id))
  (unless (non-empty-string? model-id)
    (error "model-id must be a non-empty string" model-id))
  (unless (non-empty-string? model-revision)
    (error "model-revision must be a non-empty string" model-revision))
  (unless (non-empty-string? tokenizer-revision)
    (error "tokenizer-revision must be a non-empty string" tokenizer-revision))
  (unless (non-empty-string? lens-id)
    (error "lens-id must be a non-empty string" lens-id))
  (unless (non-empty-string? lens-revision)
    (error "lens-revision must be a non-empty string" lens-revision))
  (unless (non-negative-integer? layer)
    (error "layer must be a non-negative integer" layer))
  (unless (valid-position? position)
    (error "position must be a non-negative integer or ordered token-span pair" position))
  (set! concepts (wire-list concepts))
  (set! parameters (wire-list parameters))
  (unless (and (list? concepts) (<= (length concepts) NCSI-MAX-CONCEPTS)
               (every ncsi-concept? concepts))
    (error "concepts must be a bounded list of <ncsi-concept>" concepts))
  (unless (string? readout-method)
    (error "readout-method must be a string" readout-method))
  (unless (number? reconstruction-error)
    (error "reconstruction-error must be a number" reconstruction-error))
  (unless (and (>= reconstruction-error 0.0) (<= reconstruction-error 1.0))
    (error "reconstruction-error must be in [0, 1]" reconstruction-error))
  (unless (valid-parameters? parameters)
    (error "parameters must be a bounded alist of scalar values" parameters))
  (when timestamp
    (unless (number? timestamp)
      (error "timestamp must be numeric" timestamp)))
  (let ((actual-time (or timestamp (current-time))))
    (%make-neural-observation
     schema-version
     request-id
     forward-pass-id
     model-id
     model-revision
     tokenizer-revision
     lens-id
     lens-revision
     layer
     position
     concepts
     readout-method
     parameters
     reconstruction-error
     actual-time)))

(define (observation->alist obs)
  `((schema-version . ,(obs-schema-version obs))
    (request-id . ,(obs-request-id obs))
    (forward-pass-id . ,(obs-forward-pass-id obs))
    (model-id . ,(obs-model-id obs))
    (model-revision . ,(obs-model-revision obs))
    (tokenizer-revision . ,(obs-tokenizer-revision obs))
    (lens-id . ,(obs-lens-id obs))
    (lens-revision . ,(obs-lens-revision obs))
    (layer . ,(obs-layer obs))
    (position . ,(obs-position obs))
    (concepts . ,(map concept->alist (obs-concepts obs)))
    (readout-method . ,(obs-readout-method obs))
    (parameters . ,(obs-parameters obs))
    (reconstruction-error . ,(obs-reconstruction-error obs))
    (timestamp . ,(obs-timestamp obs))))

(define (alist->observation alist)
  (let ((schema-version (wire-ref alist 'schema-version))
        (request-id (wire-ref alist 'request-id))
        (forward-pass-id (wire-ref alist 'forward-pass-id))
        (model-id (wire-ref alist 'model-id))
        (model-revision (wire-ref alist 'model-revision))
        (tokenizer-revision (wire-ref alist 'tokenizer-revision))
        (lens-id (wire-ref alist 'lens-id))
        (lens-revision (wire-ref alist 'lens-revision))
        (layer (wire-ref alist 'layer))
        (position (wire-list (wire-ref alist 'position)))
        (raw-concepts (wire-list (wire-ref alist 'concepts)))
        (readout-method (wire-ref alist 'readout-method))
        (parameters (wire-list (wire-ref alist 'parameters)))
        ;; Reconstruction error is optional quality metadata; absent means the
        ;; producer did not report an error and is represented as 0.0.
        (reconstruction-error (if (wire-has-key? alist 'reconstruction-error)
                                  (wire-ref alist 'reconstruction-error)
                                  0.0))
        (timestamp (wire-ref alist 'timestamp)))
    (unless (equal? schema-version NCSI-SCHEMA-VERSION)
      (error "Incompatible NCSI schema version in observation" schema-version))
    (unless (number? timestamp)
      (error "NCSI_INVALID_PAYLOAD: observation timestamp is required" timestamp))
    (make-ncsi-neural-observation
     #:schema-version schema-version
     #:request-id request-id
     #:forward-pass-id forward-pass-id
     #:model-id model-id
     #:model-revision model-revision
     #:tokenizer-revision tokenizer-revision
     #:lens-id lens-id
     #:lens-revision lens-revision
     #:layer layer
     #:position position
     #:concepts (map (lambda (item)
                       (if (ncsi-concept? item) item (alist->concept item)))
                     raw-concepts)
     #:readout-method readout-method
     #:parameters parameters
     #:reconstruction-error reconstruction-error
     #:timestamp timestamp)))

(define* (observation->cognitive-object obs #:key (confidence 1.0))
  "Convert a validated NCSI Neural Observation into a GAIA Cognitive Object with NEURAL_J_LENS provenance."
  (let* ((top-concepts (map (lambda (c)
                              `((token . ,(concept-token-id c))
                                (text . ,(concept-display-text c))
                                (score . ,(concept-score c))))
                            (obs-concepts obs)))
         (content `((type . neural-activation)
                    (layer . ,(obs-layer obs))
                    (position . ,(obs-position obs))
                    (concepts . ,top-concepts)
                    (reconstruction-error . ,(obs-reconstruction-error obs))))
         (relations `((request-id . ,(obs-request-id obs))
                      (forward-pass-id . ,(obs-forward-pass-id obs))
                      (model . ,(string-append (obs-model-id obs) "@" (obs-model-revision obs)))
                      (lens . ,(string-append (obs-lens-id obs) "@" (obs-lens-revision obs)))
                      (tokenizer . ,(obs-tokenizer-revision obs)))))
    (make-cognitive-object
     'observation
     content
     #:provenance 'NEURAL_J_LENS
     #:epistemic-status 'UNKNOWN
     #:verification-status 'UNVERIFIED
     #:confidence confidence
     #:relations relations)))

;; -----------------------------------------------------------------------------
;; 3. NCSI Event Union
;; -----------------------------------------------------------------------------
(define-record-type <ncsi-event>
  (%make-ncsi-event type request-id payload timestamp)
  ncsi-event?
  (type ncsi-event-type)
  (request-id ncsi-event-request-id)
  (payload ncsi-event-payload)
  (timestamp ncsi-event-timestamp))

(define* (make-ncsi-event type request-id payload #:optional timestamp)
  (unless (memq type '(GenerationStarted TokenDelta NeuralStateObserved GenerationCompleted GenerationFailed))
    (error "Invalid NCSI event type" type))
  (unless (non-empty-string? request-id)
    (error "request-id must be a non-empty string" request-id))
  (when timestamp
    (unless (number? timestamp)
      (error "timestamp must be numeric" timestamp)))
  (%make-ncsi-event type request-id payload (or timestamp (current-time))))

(define* (make-ncsi-generation-started request-id model-id #:key (timestamp #f))
  (make-ncsi-event 'GenerationStarted request-id
                   `((model-id . ,model-id))
                   timestamp))

(define* (make-ncsi-token-delta request-id token-id token-text #:key (timestamp #f))
  (make-ncsi-event 'TokenDelta request-id
                   `((token-id . ,token-id)
                     (token-text . ,token-text))
                   timestamp))

(define* (make-ncsi-neural-state-observed observation #:key (timestamp #f))
  (unless (ncsi-neural-observation? observation)
    (error "make-ncsi-neural-state-observed requires <ncsi-neural-observation>" observation))
  (make-ncsi-event 'NeuralStateObserved
                   (obs-request-id observation)
                   observation
                   timestamp))

(define* (make-ncsi-generation-completed request-id final-text #:key (token-count #f) (timestamp #f))
  (make-ncsi-event 'GenerationCompleted request-id
                   `((final-text . ,final-text)
                     (token-count . ,token-count))
                   timestamp))

(define* (make-ncsi-generation-failed request-id error-code error-message #:key (timestamp #f))
  (make-ncsi-event 'GenerationFailed request-id
                   `((error-code . ,error-code)
                     (error-message . ,error-message))
                   timestamp))

(define (ncsi-event->alist event)
  `((schema-version . ,NCSI-SCHEMA-VERSION)
    (event-type . ,(ncsi-event-type event))
    (request-id . ,(ncsi-event-request-id event))
    (timestamp . ,(ncsi-event-timestamp event))
    (payload . ,(let ((p (ncsi-event-payload event)))
                  (if (ncsi-neural-observation? p)
                      (observation->alist p)
                      p)))))

(define (required-payload-field payload key predicate label)
  (let ((value (wire-ref payload key)))
    (unless (predicate value)
      (error "NCSI_INVALID_PAYLOAD: invalid required field" label value))
    value))

(define (validate-ncsi-payload type request-id payload)
  (unless (list? payload)
    (error "NCSI_INVALID_PAYLOAD: payload must be an alist" payload))
  (case type
    ((GenerationStarted)
     (required-payload-field payload 'model-id non-empty-string? 'model-id))
    ((TokenDelta)
     (required-payload-field payload 'token-id
                             (lambda (value) (or (integer? value) (string? value)))
                             'token-id)
     (required-payload-field payload 'token-text string? 'token-text))
    ((NeuralStateObserved)
     (let ((observation (alist->observation payload)))
       (unless (equal? request-id (obs-request-id observation))
         (error "NCSI_INVALID_PAYLOAD: envelope and observation request-id differ"
                request-id (obs-request-id observation)))))
    ((GenerationCompleted)
     (required-payload-field payload 'final-text string? 'final-text)
     (let ((token-count (wire-ref payload 'token-count)))
       (when (wire-has-key? payload 'token-count)
         (unless (non-negative-integer? token-count)
           (error "NCSI_INVALID_PAYLOAD: token-count must be non-negative" token-count)))))
    ((GenerationFailed)
     (required-payload-field payload 'error-code non-empty-string? 'error-code)
     (required-payload-field payload 'error-message non-empty-string? 'error-message))))

(define (validate-ncsi-event alist)
  (unless (list? alist)
    (error "NCSI_MALFORMED_EVENT: expected an alist representation" alist))
  (let ((schema (wire-ref alist 'schema-version))
        (type (wire-event-type (wire-ref alist 'event-type)))
        (req-id (wire-ref alist 'request-id))
        (timestamp (wire-ref alist 'timestamp))
        (payload (wire-ref alist 'payload)))
    (unless (equal? schema NCSI-SCHEMA-VERSION)
      (error "NCSI_INCOMPATIBLE_VERSION: unsupported schema version" schema))
    (unless (memq type '(GenerationStarted TokenDelta NeuralStateObserved GenerationCompleted GenerationFailed))
      (error "NCSI_MALFORMED_EVENT: unknown event type" type))
    (unless (non-empty-string? req-id)
      (error "NCSI_INVALID_PAYLOAD: missing or invalid request-id" req-id))
    (unless (number? timestamp)
      (error "NCSI_INVALID_PAYLOAD: event timestamp is required" timestamp))
    (validate-ncsi-payload type req-id payload)
    #t))

(define (parse-ncsi-event sexp-or-alist)
  (validate-ncsi-event sexp-or-alist)
  (let* ((type (wire-event-type (wire-ref sexp-or-alist 'event-type)))
         (req-id (wire-ref sexp-or-alist 'request-id))
         (timestamp (wire-ref sexp-or-alist 'timestamp))
         (raw-payload (wire-ref sexp-or-alist 'payload))
         (payload (if (eq? type 'NeuralStateObserved)
                      (alist->observation raw-payload)
                      raw-payload)))
    (make-ncsi-event type req-id payload timestamp)))
