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

;; -----------------------------------------------------------------------------
;; 1. NCSI Concept
;; -----------------------------------------------------------------------------
(define-record-type <ncsi-concept>
  (%make-concept token-id display-text score)
  ncsi-concept?
  (token-id concept-token-id)
  (display-text concept-display-text)
  (score concept-score))

(define* (make-ncsi-concept token-id display-text score)
  (unless (or (integer? token-id) (string? token-id))
    (error "Concept token-id must be an integer or string" token-id))
  (unless (string? display-text)
    (error "Concept display-text must be a string" display-text))
  (unless (number? score)
    (error "Concept score must be a number" score))
  (%make-concept token-id display-text score))

(define (concept->alist concept)
  `((token-id . ,(concept-token-id concept))
    (display-text . ,(concept-display-text concept))
    (score . ,(concept-score concept))))

(define (alist->concept alist)
  (let ((token-id (assoc-ref alist 'token-id))
        (display-text (assoc-ref alist 'display-text))
        (score (assoc-ref alist 'score)))
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
  (unless (and (string? request-id) (> (string-length request-id) 0))
    (error "request-id must be a non-empty string" request-id))
  (unless (and (string? forward-pass-id) (> (string-length forward-pass-id) 0))
    (error "forward-pass-id must be a non-empty string" forward-pass-id))
  (unless (and (string? model-id) (> (string-length model-id) 0))
    (error "model-id must be a non-empty string" model-id))
  (unless (and (string? model-revision) (> (string-length model-revision) 0))
    (error "model-revision must be a non-empty string" model-revision))
  (unless (and (string? tokenizer-revision) (> (string-length tokenizer-revision) 0))
    (error "tokenizer-revision must be a non-empty string" tokenizer-revision))
  (unless (and (string? lens-id) (> (string-length lens-id) 0))
    (error "lens-id must be a non-empty string" lens-id))
  (unless (and (string? lens-revision) (> (string-length lens-revision) 0))
    (error "lens-revision must be a non-empty string" lens-revision))
  (unless (integer? layer)
    (error "layer must be an integer" layer))
  (unless (or (integer? position) (pair? position))
    (error "position must be an integer or token-span pair" position))
  (unless (and (list? concepts) (every ncsi-concept? concepts))
    (error "concepts must be a list of <ncsi-concept>" concepts))
  (unless (string? readout-method)
    (error "readout-method must be a string" readout-method))
  (unless (number? reconstruction-error)
    (error "reconstruction-error must be a number" reconstruction-error))
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
  (let ((schema-version (assoc-ref alist 'schema-version))
        (request-id (assoc-ref alist 'request-id))
        (forward-pass-id (assoc-ref alist 'forward-pass-id))
        (model-id (assoc-ref alist 'model-id))
        (model-revision (assoc-ref alist 'model-revision))
        (tokenizer-revision (assoc-ref alist 'tokenizer-revision))
        (lens-id (assoc-ref alist 'lens-id))
        (lens-revision (assoc-ref alist 'lens-revision))
        (layer (assoc-ref alist 'layer))
        (position (assoc-ref alist 'position))
        (raw-concepts (or (assoc-ref alist 'concepts) '()))
        (readout-method (or (assoc-ref alist 'readout-method) "jlens-sparse"))
        (parameters (or (assoc-ref alist 'parameters) '()))
        (reconstruction-error (or (assoc-ref alist 'reconstruction-error) 0.0))
        (timestamp (assoc-ref alist 'timestamp)))
    (unless (equal? schema-version NCSI-SCHEMA-VERSION)
      (error "Incompatible NCSI schema version in observation" schema-version))
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
  (unless (and (string? request-id) (> (string-length request-id) 0))
    (error "request-id must be a non-empty string" request-id))
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

(define (validate-ncsi-event alist)
  (unless (list? alist)
    (error "NCSI_MALFORMED_EVENT: expected an alist representation" alist))
  (let ((schema (assoc-ref alist 'schema-version))
        (type (assoc-ref alist 'event-type))
        (req-id (assoc-ref alist 'request-id)))
    (unless (equal? schema NCSI-SCHEMA-VERSION)
      (error "NCSI_INCOMPATIBLE_VERSION: unsupported schema version" schema))
    (unless (memq type '(GenerationStarted TokenDelta NeuralStateObserved GenerationCompleted GenerationFailed))
      (error "NCSI_MALFORMED_EVENT: unknown event type" type))
    (unless (and (string? req-id) (> (string-length req-id) 0))
      (error "NCSI_INVALID_PAYLOAD: missing or invalid request-id" req-id))
    #t))

(define (parse-ncsi-event sexp-or-alist)
  (validate-ncsi-event sexp-or-alist)
  (let* ((type (assoc-ref sexp-or-alist 'event-type))
         (req-id (assoc-ref sexp-or-alist 'request-id))
         (timestamp (or (assoc-ref sexp-or-alist 'timestamp) (current-time)))
         (raw-payload (or (assoc-ref sexp-or-alist 'payload) '()))
         (payload (if (eq? type 'NeuralStateObserved)
                      (alist->observation raw-payload)
                      raw-payload)))
    (make-ncsi-event type req-id payload timestamp)))
