(define-module (gaia cognitive-memory)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 ftw)
  #:use-module (gaia com)
  #:export (<cognitive-memory>
            make-cognitive-memory
            cognitive-memory?
            memory-objects
            memory-role
            VALID-MEMORY-ROLES
            memory-store!
            memory-consolidate!
            memory-object-by-id
            memory-link!
            memory-related
            memory-neighborhood
            memory-dependents
            memory-invalidate!
            memory-supersede!
            memory-revise!
            memory-activation
            memory-activate!
            memory-retrieve
            memory-retrieve-facts
            make-user-memory-claim
            reconstruct-context))

;; Episodic/semantic COs are stored independently from chat transcripts.  The
;; optional S-expression file is a transparent, local durability mechanism for
;; GCAS-Core; a database backend can replace it without changing retrieval.
(define VALID-MEMORY-ROLES
  '(EPISODIC SEMANTIC PROCEDURAL USER_TESTIMONY METACOGNITIVE))

(define-record-type <cognitive-memory>
  (%make-memory objects-cell path activation-cell active-limit)
  cognitive-memory?
  (objects-cell memory-objects-cell)
  (path memory-path)
  ;; STI is a rebuildable, non-authoritative projection.  It is deliberately
  ;; not serialized with durable Cognitive Objects.
  (activation-cell memory-activation-cell)
  (active-limit memory-active-limit))

(define (load-objects path)
  (if (and path (file-exists? path))
      (call-with-input-file path
        (lambda (port)
          (let ((data (read port)))
            (if (list? data) (map alist->co data) '()))))
      '()))

(define* (make-cognitive-memory #:key (path #f) (restore? #t) (active-limit 512))
  (unless (and (integer? active-limit) (> active-limit 0))
    (error "Cognitive Memory active limit must be a positive integer"
           active-limit))
  (let ((memory (%make-memory (list (if restore? (load-objects path) '()))
                              path (list '()) active-limit)))
    ;; `/clear` must establish a new durable memory boundary rather than loading
    ;; the preceding session's memories on the next constructor call.
    (when (and path (not restore?))
      (persist! memory))
    memory))

(define (memory-objects memory)
  (car (memory-objects-cell memory)))

(define (memory-role co)
  "Return CO's explicit memory role, or #f when it has not been consolidated."
  (and (cognitive-object? co) (assoc-ref (co-relations co) 'memory-role)))

(define (validate-memory-role! co)
  (let ((role (memory-role co)))
    (when (and role (not (memq role VALID-MEMORY-ROLES)))
      (error "Invalid GCAS memory role" role (co-id co)))))

(define (persist! memory)
  (let ((path (memory-path memory)))
    (when path
      (let ((directory (dirname path)))
        (unless (file-exists? directory)
          (mkdir directory)))
      (call-with-output-file path
        (lambda (port) (write (map co->alist (memory-objects memory)) port))))))

(define (memory-store! memory co)
  (unless (and (cognitive-memory? memory) (cognitive-object? co))
    (error "Memory stores Cognitive Objects" memory co))
  (validate-memory-role! co)
  (let ((existing (memory-objects memory)))
    (set-car! (memory-objects-cell memory)
              (cons co (filter (lambda (old) (not (equal? (co-id old) (co-id co)))) existing))))
  (persist! memory)
  co)

(define (memory-object-by-id memory object-id)
  "Return the durable Cognitive Object identified by OBJECT-ID, or #f."
  (and (cognitive-memory? memory)
       (find (lambda (co) (equal? (co-id co) object-id))
             (memory-objects memory))))

(define (require-memory-object memory object-id label)
  (or (memory-object-by-id memory object-id)
      (error (format #f "~a requires a stored Cognitive Object" label)
             object-id)))

(define (relation-present? co relation-type target-id)
  (any (lambda (relation)
         (and (eq? (car relation) relation-type)
              (equal? (cdr relation) target-id)))
       (co-relations co)))

(define (memory-link! memory source-id relation-type target-id)
  "Persist a typed directed edge from SOURCE-ID to TARGET-ID.

Both endpoints must already exist. Repeating the same edge is idempotent."
  (unless (symbol? relation-type)
    (error "Memory relation type must be a symbol" relation-type))
  (let ((source (require-memory-object memory source-id "memory-link!")))
    (require-memory-object memory target-id "memory-link!")
    (if (relation-present? source relation-type target-id)
        source
        (memory-store! memory
                       (co-add-relation source relation-type target-id)))))

(define (unique-cos objects)
  (fold (lambda (co result)
          (if (any (lambda (existing) (equal? (co-id existing) (co-id co)))
                   result)
              result
              (append result (list co))))
        '()
        objects))

(define* (memory-related memory object-id
                         #:key relation-type (direction 'outgoing))
  "Resolve graph neighbors of OBJECT-ID.

DIRECTION is `outgoing' or `incoming'. RELATION-TYPE optionally restricts the
edge type. Only relations whose endpoint is another stored CO are returned."
  (unless (memq direction '(outgoing incoming))
    (error "Memory relation direction must be outgoing or incoming" direction))
  (when relation-type
    (unless (symbol? relation-type)
      (error "Memory relation type must be a symbol" relation-type)))
  (require-memory-object memory object-id "memory-related")
  (unique-cos
   (if (eq? direction 'outgoing)
       (filter-map
        (lambda (relation)
          (and (or (not relation-type) (eq? (car relation) relation-type))
               (string? (cdr relation))
               (memory-object-by-id memory (cdr relation))))
        (co-relations (memory-object-by-id memory object-id)))
       (filter
        (lambda (candidate)
          (any (lambda (relation)
                 (and (or (not relation-type)
                          (eq? (car relation) relation-type))
                      (equal? (cdr relation) object-id)))
               (co-relations candidate)))
        (memory-objects memory)))))

(define* (memory-neighborhood memory seed-ids
                              #:key
                              (depth 2)
                              (limit 128)
                              relation-types)
  "Return a bounded graph neighborhood around stored SEED-IDS.

Traversal follows both incoming and outgoing typed relations. It is a
retrieval projection only and never changes epistemic or verification state."
  (unless (and (integer? depth) (>= depth 0)
               (integer? limit) (> limit 0))
    (error "Invalid bounded memory traversal" depth limit))
  (let loop ((queue (map (lambda (id) (cons id 0))
                         (filter (lambda (id)
                                   (memory-object-by-id memory id))
                                 seed-ids)))
             (visited '())
             (result '()))
    (if (or (null? queue) (>= (length result) limit))
        result
        (let* ((item (car queue))
               (current-id (car item))
               (current-depth (cdr item)))
          (if (member current-id visited)
              (loop (cdr queue) visited result)
              (let* ((current (memory-object-by-id memory current-id))
                     (neighbors
                      (if (>= current-depth depth)
                          '()
                          (filter
                           (lambda (candidate)
                             (or (not relation-types)
                                 (any
                                  (lambda (relation)
                                    (and (memq (car relation) relation-types)
                                         (or (equal? (cdr relation)
                                                     (co-id candidate))
                                             (equal? (cdr relation)
                                                     current-id))))
                                  (append (co-relations current)
                                          (co-relations candidate)))))
                           (unique-cos
                            (append
                             (memory-related memory current-id
                                             #:direction 'outgoing)
                             (memory-related memory current-id
                                             #:direction 'incoming))))))
                     (new-items
                      (map (lambda (co)
                             (cons (co-id co) (+ current-depth 1)))
                           neighbors)))
                (loop (append (cdr queue) new-items)
                      (cons current-id visited)
                      (append result (list current)))))))))

(define* (memory-dependents memory object-id
                            #:key
                            (relation-types '(derived-from assumes supported-by)))
  "Return Claims whose declared justification depends on OBJECT-ID."
  (require-memory-object memory object-id "memory-dependents")
  (filter
   (lambda (candidate)
     (any (lambda (relation)
            (and (memq (car relation) relation-types)
                 (equal? (cdr relation) object-id)))
          (co-relations candidate)))
   (memory-objects memory)))

(define (invalidate-object! memory co invalidator-id)
  (if (co-invalidated-by co)
      co
      (memory-store!
       memory
       (co-update-epistemic co
                            (co-epistemic-status co)
                            (co-verification-status co)
                            (co-confidence co)
                            invalidator-id))))

(define* (memory-invalidate! memory object-id invalidator-id
                             #:key
                             (relation-types '(derived-from assumes supported-by)))
  "Invalidate OBJECT-ID and transitively invalidate its justification dependents.

The invalidating CO must already be stored, preserving an auditable cause. The
operation is duplicate-safe and retains every historical object."
  (let ((invalidator
         (require-memory-object memory invalidator-id "memory-invalidate!")))
    (require-memory-object memory object-id "memory-invalidate!")
    (memory-link! memory invalidator-id 'invalidates object-id)
    (let walk ((pending (list object-id)) (visited '()) (invalidated '()))
      (if (null? pending)
          (reverse invalidated)
          (let ((current-id (car pending)))
            (if (member current-id visited)
                (walk (cdr pending) visited invalidated)
                (let* ((current (require-memory-object
                                 memory current-id "memory-invalidate!"))
                       (dependents
                        (memory-dependents memory current-id
                                           #:relation-types relation-types))
                       (updated (invalidate-object! memory current
                                                    (co-id invalidator))))
                  (walk (append (map co-id dependents) (cdr pending))
                        (cons current-id visited)
                        (cons updated invalidated)))))))))

(define (memory-supersede! memory old-id new-co)
  "Store NEW-CO as the auditable successor of OLD-ID and retire the old fact."
  (unless (cognitive-object? new-co)
    (error "memory-supersede! requires a Cognitive Object" new-co))
  (let ((old (require-memory-object memory old-id "memory-supersede!")))
    (when (equal? old-id (co-id new-co))
      (error "A superseding Cognitive Object requires a new identity" old-id))
    (let* ((successor
            (if (relation-present? new-co 'supersedes old-id)
                new-co
                (co-add-relation new-co 'supersedes old-id)))
           (retired-with-link
            (if (relation-present? old 'superseded-by (co-id successor))
                old
                (co-add-relation old 'superseded-by (co-id successor))))
           (retired
            (co-update-epistemic retired-with-link
                                 (co-epistemic-status retired-with-link)
                                 (co-verification-status retired-with-link)
                                 (co-confidence retired-with-link)
                                 (or (co-invalidated-by retired-with-link)
                                     (co-id successor)))))
      (memory-store! memory retired)
      (memory-store! memory successor)
      successor)))

(define (memory-revise! memory prior-id opposing-evidence successor)
  "Record contradiction-driven revision without erasing history.

OPPOSING-EVIDENCE and SUCCESSOR are retained with explicit roles. A fresh
Conflict invalidates PRIOR-ID and its justification dependents before SUCCESSOR
is linked as the current semantic version."
  (unless (and (cognitive-object? opposing-evidence)
               (memq (co-type opposing-evidence) '(evidence observation result)))
    (error "memory-revise! requires fresh opposing evidence"
           opposing-evidence))
  (unless (and (cognitive-object? successor) (fact? successor))
    (error "memory-revise! requires an accepted verified successor Claim"
           successor))
  (let* ((prior (require-memory-object memory prior-id "memory-revise!"))
         (retained-evidence
          (ensure-relation opposing-evidence 'memory-role 'EPISODIC))
         (conflict
          (make-cognitive-object
           'conflict
           (string-append "Fresh evidence contradicts retained Claim: "
                          (co-content prior))
           #:provenance 'SYMBOLIC_INFERENCE
           #:relations `((contradicts . ,prior-id)
                         (based-on . ,(co-id retained-evidence))
                         (memory-role . METACOGNITIVE))))
         (supported-successor
          (ensure-relation successor 'supported-by (co-id retained-evidence))))
    (memory-consolidate! memory (list retained-evidence conflict)
                         #:reason 'CONTRADICTION_REVISION
                         #:revalidation 'ON_NEW_EVIDENCE)
    (let ((invalidated (memory-invalidate! memory prior-id (co-id conflict)))
          (current (memory-supersede! memory prior-id supported-successor)))
      (memory-consolidate! memory (list current)
                           #:reason 'CONTRADICTION_REVISION
                           #:revalidation 'ON_NEW_EVIDENCE)
      (list conflict current invalidated))))

(define (default-memory-role co)
  (case (co-type co)
    ((claim) (and (fact? co) 'SEMANTIC))
    ((procedure) (and (eq? (co-epistemic-status co) 'ACCEPTED)
                      (memq (co-verification-status co)
                            '(VERIFIED FORMALLY_VERIFIED))
                      'PROCEDURAL))
    ((reflection conflict) 'METACOGNITIVE)
    ((observation) (memory-role co))
    ((evidence result) 'EPISODIC)
    (else #f)))

(define (ensure-relation co relation-type value)
  (if (assoc-ref (co-relations co) relation-type)
      co
      (co-add-relation co relation-type value)))

(define* (memory-consolidate! memory objects
                              #:key
                              (reason 'TERMINAL_PROCESS)
                              (revalidation 'ON_CONTRADICTION_OR_EXPIRY))
  "Persist governed, role-typed memory independently from transcript history.

Every retained object records why it was retained and when it must be
revalidated. Unsupported transient Goals, Questions, Plans, and Actions remain
in process state rather than silently becoming long-term memory."
  (for-each
   (lambda (co)
     (when (cognitive-object? co)
       (let ((role (or (memory-role co) (default-memory-role co))))
         (when role
           (unless (memq role VALID-MEMORY-ROLES)
             (error "Invalid GCAS memory role" role (co-id co)))
           (memory-store!
            memory
            (ensure-relation
             (ensure-relation
              (ensure-relation co 'memory-role role)
              'retention-reason reason)
             'revalidate-on revalidation))))))
   objects)
  objects)

(define (activation-entry memory object-id)
  (find (lambda (entry) (equal? (assoc-ref entry 'id) object-id))
        (car (memory-activation-cell memory))))

(define* (memory-activation memory object-id #:key (half-life 3600))
  "Return lazily decayed STI activation for OBJECT-ID.

Activation is an attention quantity only; reading it cannot alter the stored CO."
  (let ((entry (activation-entry memory object-id)))
    (if (not entry)
        0
        (let* ((age (max 0 (- (current-time) (assoc-ref entry 'updated-at))))
               (decay (/ 1.0 (+ 1.0 (/ age (max 1 half-life))))))
          (* (assoc-ref entry 'value) decay)))))

(define* (memory-activate! memory object-ids
                           #:key (amount 1.0) (policy-version 'STI-V1))
  "Raise activation for stored objects and prune the projection to top-k."
  (unless (and (number? amount) (> amount 0))
    (error "Memory activation amount must be positive" amount))
  (let* ((now (current-time))
         (valid-ids
          (delete-duplicates
           (filter (lambda (id) (memory-object-by-id memory id)) object-ids)))
         (untouched
          (filter (lambda (entry)
                    (not (member (assoc-ref entry 'id) valid-ids)))
                  (car (memory-activation-cell memory))))
         (updated
          (map (lambda (id)
                 `((id . ,id)
                   (value . ,(+ amount (memory-activation memory id)))
                   (updated-at . ,now)
                   (policy-version . ,policy-version)))
               valid-ids))
         (ranked
          (sort (append updated untouched)
                (lambda (left right)
                  (> (assoc-ref left 'value) (assoc-ref right 'value))))))
    (set-car! (memory-activation-cell memory)
              (take ranked (min (memory-active-limit memory) (length ranked))))
    (map (lambda (id) (memory-activation memory id)) valid-ids)))

(define (tokenize text)
  (filter (lambda (token) (> (string-length token) 1))
          (string-tokenize (string-downcase (format #f "~a" text)))))

(define (overlap-score query candidate)
  (length (lset-intersection string=? (tokenize query) (tokenize (co-content candidate)))))

(define (user-assertion? text)
  (let ((normalized (string-downcase text)))
    (any (lambda (marker) (string-contains normalized marker))
         '("my name is" "mam na imię" "nazywam się" "i prefer" "preferuję"
           "my favourite" "my favorite" "moim ulubionym" "lubię"))))

(define (make-user-memory-claim text)
  "Represent an explicit user assertion as an unverified Observation.

The system observed that the user supplied the statement; it does not thereby
accept the proposition expressed by the statement as a verified world fact."
  (and (string? text)
       (user-assertion? text)
       (make-cognitive-object
        'observation (string-append "User stated: " text)
        #:provenance 'USER
        #:relations '((memory-role . USER_TESTIMONY)))))

(define (temporally-valid? co)
  (let ((now (current-time)))
    (and (<= (co-valid-from co) now)
         (not (co-invalidated-by co))
         (or (eq? (co-valid-to co) 'INF)
             (>= (co-valid-to co) now)))))

(define (current-memory-object? co)
  (and (temporally-valid? co)
       (not (assoc-ref (co-relations co) 'superseded-by))
       (case (co-type co)
         ((claim) (fact? co))
         ((procedure)
          (and (eq? (co-epistemic-status co) 'ACCEPTED)
               (memq (co-verification-status co)
                     '(VERIFIED FORMALLY_VERIFIED))))
         ((observation) (eq? (memory-role co) 'USER_TESTIMONY))
         ((evidence result conflict reflection) #t)
         (else #f))))

(define (role-score co)
  (case (memory-role co)
    ((SEMANTIC PROCEDURAL) 3)
    ((USER_TESTIMONY) 2)
    ((EPISODIC METACOGNITIVE) 1)
    (else 0)))

(define (provenance-score co)
  (case (co-provenance co)
    ((FORMAL_PROOF EXECUTION SYMBOLIC_INFERENCE) 2)
    ((USER EXTERNAL_SOURCE SENSOR REPL) 1)
    (else 0)))

(define* (memory-retrieve memory goal
                          #:key
                          (limit 5)
                          (depth 2)
                          (graph-limit 128))
  "Retrieve bounded Goal-relevant memory using content, graph, provenance,
validity, contradiction state, role, and STI activation.

Lexical matches seed a bounded graph traversal. Retrieval and activation are
epistemically neutral; invalidated, expired, or superseded Claims are never
eligible as current facts."
  (let* ((goal-text (if (cognitive-object? goal) (co-content goal) goal))
         (eligible (filter current-memory-object? (memory-objects memory)))
         (lexical
          (map (lambda (co) (cons co (overlap-score goal-text co))) eligible))
         (seeds
          (map (lambda (pair) (co-id (car pair)))
               (filter (lambda (pair) (> (cdr pair) 0)) lexical)))
         (neighborhood
          (if (null? seeds)
              '()
              (memory-neighborhood memory seeds #:depth depth
                                   #:limit graph-limit)))
         (neighbor-ids (map co-id neighborhood))
         (scored
          (filter-map
           (lambda (pair)
             (let* ((co (car pair))
                    (lexical-score (cdr pair))
                    (graph-score (if (member (co-id co) neighbor-ids) 2 0))
                    (score (+ (* 4 lexical-score)
                              graph-score
                              (role-score co)
                              (provenance-score co)
                              (memory-activation memory (co-id co)))))
               (and (> score 0) (cons co score))))
           lexical))
         (selected
          (map car
               (take (sort scored
                           (lambda (left right) (> (cdr left) (cdr right))))
                     (min limit (length scored))))))
    (memory-activate! memory (map co-id selected))
    selected))

(define* (memory-retrieve-facts memory goal #:key (limit 3) (minimum-overlap 2))
  "Return accepted facts sufficiently related to GOAL for memory-only answering."
  (let ((scored
         (filter (lambda (pair) (>= (cdr pair) minimum-overlap))
                 (map (lambda (co) (cons co (overlap-score goal co)))
                      (filter (lambda (co)
                                (and (fact? co)
                                     (temporally-valid? co)
                                     (not (assoc-ref (co-relations co)
                                                     'superseded-by))))
                              (memory-objects memory))))))
    (let ((selected
           (map car
                (take (sort scored
                            (lambda (left right) (> (cdr left) (cdr right))))
                      (min limit (length scored))))))
      (memory-activate! memory (map co-id selected))
      selected)))

(define* (reconstruct-context goal active-workspace selected-memories
                            #:key (constraints '()))
  "Build the non-transcript prompt context from explicit GCAS state."
  (define (render label objects)
    (string-append label "\n"
                   (if (null? objects) "- none\n"
                       (string-join
                        (map (lambda (co) (string-append "- [" (symbol->string (co-type co)) "] " (co-content co) "\n"))
                             objects) ""))))
  (string-append
   "Current goal:\n" (co-content goal) "\n\n"
   (render "Admitted workspace:" active-workspace) "\n"
   (render "Retrieved structured memory:" selected-memories) "\n"
   "Active constraints:\n"
   (if (null? constraints) "- Treat model output as an unverified hypothesis.\n"
       (string-join (map (lambda (constraint) (string-append "- " constraint "\n")) constraints) ""))))
