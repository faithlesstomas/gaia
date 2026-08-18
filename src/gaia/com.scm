(define-module (gaia com)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (ice-9 match)
  #:export (<cognitive-object>
            make-cognitive-object
            cognitive-object?
            co-id
            co-type
            co-content
            co-provenance
            co-epistemic-status
            co-verification-status
            co-confidence
            co-valid-from
            co-valid-to
            co-invalidated-by
            co-relations
            fact?
            hypothesis?
            co->alist
            alist->co
            co-update-epistemic
            co-add-relation
            VALID-PROVENANCES
            VALID-EPISTEMIC-STATUSES
            VALID-VERIFICATION-STATUSES
            VALID-TYPES))

;; Permissible values per GCAS 0.1 taxonomy
(define VALID-TYPES
  '(claim hypothesis observation evidence goal plan action result question conflict reflection rule procedure))

(define VALID-PROVENANCES
  '(USER LLM REPL SENSOR MEMORY EXTERNAL_SOURCE SYMBOLIC_INFERENCE FORMAL_PROOF EXECUTION NEURAL NEURAL_J_LENS))

(define VALID-EPISTEMIC-STATUSES
  '(UNKNOWN HYPOTHESIS ASSUMPTION BELIEF ACCEPTED REFUTED DISPUTED))

(define VALID-VERIFICATION-STATUSES
  '(UNVERIFIED PARTIALLY_VERIFIED VERIFIED FORMALLY_VERIFIED))

(define (valid-member? value allowed label)
  (unless (memq value allowed)
    (error (format #f "Invalid ~a: ~s" label value))))

(define (valid-confidence? value)
  (unless (and (number? value) (<= 0 value 1))
    (error (format #f "Confidence must be a number in [0, 1]: ~s" value))))

(define (valid-temporal-interval? valid-from valid-to)
  (unless (and (number? valid-from)
               (or (eq? valid-to 'INF)
                   (and (number? valid-to) (>= valid-to valid-from))))
    (error (format #f "Invalid temporal validity interval: [~s, ~s]"
                   valid-from valid-to))))

;; Definition of Cognitive Object Record
(define-record-type <cognitive-object>
  (%make-co id type content provenance epistemic-status verification-status confidence valid-from valid-to invalidated-by relations)
  cognitive-object?
  (id co-id)
  (type co-type)
  (content co-content)
  (provenance co-provenance)
  (epistemic-status co-epistemic-status)
  (verification-status co-verification-status)
  (confidence co-confidence)
  (valid-from co-valid-from)
  (valid-to co-valid-to)
  (invalidated-by co-invalidated-by)
  (relations co-relations))

(define (generate-co-id)
  (format #f "co-~a-~a" (current-time) (random 1000000)))

(define* (make-cognitive-object type content
                                #:key
                                (id #f)
                                (provenance 'LLM)
                                (epistemic-status #f)
                                (verification-status #f)
                                (confidence 1.0)
                                (valid-from #f)
                                (valid-to 'INF)
                                (invalidated-by #f)
                                (relations '()))
  "Constructor for Cognitive Objects enforcing GCAS epistemic classification rules."
  (valid-member? type VALID-TYPES 'Cognitive-Object-type)
  (valid-member? provenance VALID-PROVENANCES 'provenance)
  (valid-confidence? confidence)
  (let* ((actual-valid-from (or valid-from (current-time)))
         (actual-id (or id (generate-co-id)))
         ;; Rule 1: LLM outputs automatically carry HYPOTHESIS & UNVERIFIED unless specified
         (actual-epistemic
          (or epistemic-status
              (case provenance
                ((LLM) 'HYPOTHESIS)
                ((USER SENSOR REPL EXECUTION) 'UNKNOWN)
                ((FORMAL_PROOF SYMBOLIC_INFERENCE) 'BELIEF)
                (else 'UNKNOWN))))
         (actual-verification
          (or verification-status
              (case provenance
                ((FORMAL_PROOF) 'FORMALLY_VERIFIED)
                ((REPL EXECUTION) 'UNVERIFIED)
                ((LLM USER SENSOR) 'UNVERIFIED)
                (else 'UNVERIFIED)))))
    (valid-member? actual-epistemic VALID-EPISTEMIC-STATUSES 'epistemic-status)
    (valid-member? actual-verification VALID-VERIFICATION-STATUSES 'verification-status)
    (valid-temporal-interval? actual-valid-from valid-to)
    ;; An LLM proposal must cross an explicit verification/update boundary before
    ;; it can become accepted knowledge.  Provenance remains LLM afterwards.
    (when (and (eq? provenance 'LLM)
               (or (not (eq? actual-epistemic 'HYPOTHESIS))
                   (not (eq? actual-verification 'UNVERIFIED))))
      (error "LLM output must initially be HYPOTHESIS and UNVERIFIED"))
    ;; A neural signal enters GAIA as an observation or proposal, never as an accepted or verified fact.
    (when (and (memq provenance '(NEURAL NEURAL_J_LENS))
               (or (eq? actual-epistemic 'ACCEPTED)
                   (memq actual-verification '(VERIFIED FORMALLY_VERIFIED))))
      (error "Neural signals cannot initially be ACCEPTED or VERIFIED"))
    (%make-co actual-id type content provenance actual-epistemic actual-verification confidence actual-valid-from valid-to invalidated-by relations)))

(define (fact? co)
  "Predicate: Returns #t if Cognitive Object is an ACCEPTED Fact with VERIFIED or FORMALLY_VERIFIED status."
  (and (cognitive-object? co)
       (eq? (co-type co) 'claim)
       (eq? (co-epistemic-status co) 'ACCEPTED)
       (memq (co-verification-status co) '(VERIFIED FORMALLY_VERIFIED))))

(define (hypothesis? co)
  "Predicate: Returns #t if Cognitive Object is a HYPOTHESIS."
  (and (cognitive-object? co)
       (eq? (co-epistemic-status co) 'HYPOTHESIS)))

(define (co-update-epistemic co new-epistemic new-verification . optional-args)
  "Immutably creates a new Cognitive Object with updated epistemic/verification status and optional new confidence & invalidated-by tag."
  (valid-member? new-epistemic VALID-EPISTEMIC-STATUSES 'epistemic-status)
  (valid-member? new-verification VALID-VERIFICATION-STATUSES 'verification-status)
  (let ((new-confidence (if (null? optional-args) (co-confidence co) (car optional-args)))
        (new-invalidated (if (or (null? optional-args) (null? (cdr optional-args))) (co-invalidated-by co) (cadr optional-args))))
    (valid-confidence? new-confidence)
    (%make-co (co-id co)
              (co-type co)
              (co-content co)
              (co-provenance co)
              new-epistemic
              new-verification
              new-confidence
              (co-valid-from co)
              (co-valid-to co)
              new-invalidated
              (co-relations co))))

(define (co-add-relation co relation-type target-id)
  "Immutably adds a relational link ((relation-type . target-id)) to Cognitive Object."
  (%make-co (co-id co)
            (co-type co)
            (co-content co)
            (co-provenance co)
            (co-epistemic-status co)
            (co-verification-status co)
            (co-confidence co)
            (co-valid-from co)
            (co-valid-to co)
            (co-invalidated-by co)
            (cons (cons relation-type target-id) (co-relations co))))

(define (co->alist co)
  "Serializes Cognitive Object to Guile alist for IPC / Goblins actor transmission."
  `(("id" . ,(co-id co))
    ("type" . ,(symbol->string (co-type co)))
    ("content" . ,(co-content co))
    ("provenance" . ,(symbol->string (co-provenance co)))
    ("epistemic-status" . ,(symbol->string (co-epistemic-status co)))
    ("verification-status" . ,(symbol->string (co-verification-status co)))
    ("confidence" . ,(co-confidence co))
    ("valid-from" . ,(co-valid-from co))
    ("valid-to" . ,(if (symbol? (co-valid-to co)) (symbol->string (co-valid-to co)) (co-valid-to co)))
    ("invalidated-by" . ,(or (co-invalidated-by co) "null"))
    ("relations" . ,(map (lambda (p) (cons (symbol->string (car p)) (cdr p))) (co-relations co)))))

(define (alist->co alist)
  "Deserialize and validate a persisted Cognitive Object.

Restoration deliberately permits an LLM-origin object that crossed a recorded
verification boundary after creation, but never permits malformed ontology,
confidence, or temporal metadata to enter Cognitive State."
  (let ((id (assoc-ref alist "id"))
        (type (string->symbol (or (assoc-ref alist "type") "claim")))
        (content (or (assoc-ref alist "content") ""))
        (prov (string->symbol (or (assoc-ref alist "provenance") "LLM")))
        (epistemic (string->symbol (or (assoc-ref alist "epistemic-status") "HYPOTHESIS")))
        (verif (string->symbol (or (assoc-ref alist "verification-status") "UNVERIFIED")))
        (conf (or (assoc-ref alist "confidence") 1.0))
        (valid-from (or (assoc-ref alist "valid-from") 0))
        (valid-to-val (assoc-ref alist "valid-to"))
        (invalidated-by (let ((inv (assoc-ref alist "invalidated-by")))
                          (if (or (not inv) (string=? inv "null")) #f inv)))
        (relations (let ((rel (assoc-ref alist "relations")))
                     (if rel
                         (map (lambda (pair) (cons (string->symbol (car pair)) (cdr pair))) rel)
                         '()))))
    (let ((valid-to (if (and (string? valid-to-val) (string=? valid-to-val "INF"))
                        'INF valid-to-val)))
      (unless (and (string? id) (positive? (string-length id)))
        (error "Persisted Cognitive Object requires a non-empty id" id))
      (valid-member? type VALID-TYPES 'Cognitive-Object-type)
      (valid-member? prov VALID-PROVENANCES 'provenance)
      (valid-member? epistemic VALID-EPISTEMIC-STATUSES 'epistemic-status)
      (valid-member? verif VALID-VERIFICATION-STATUSES 'verification-status)
      (valid-confidence? conf)
      (valid-temporal-interval? valid-from valid-to)
      (%make-co id type content prov epistemic verif conf valid-from valid-to
                invalidated-by relations))))
