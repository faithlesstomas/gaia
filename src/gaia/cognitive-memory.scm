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
            memory-store!
            memory-consolidate!
            memory-object-by-id
            memory-link!
            memory-related
            memory-dependents
            memory-invalidate!
            memory-supersede!
            memory-retrieve
            memory-retrieve-facts
            make-user-memory-claim
            reconstruct-context))

;; Episodic/semantic COs are stored independently from chat transcripts.  The
;; optional S-expression file is a transparent, local durability mechanism for
;; GCAS-Core; a database backend can replace it without changing retrieval.
(define-record-type <cognitive-memory>
  (%make-memory objects-cell path)
  cognitive-memory?
  (objects-cell memory-objects-cell)
  (path memory-path))

(define (load-objects path)
  (if (and path (file-exists? path))
      (call-with-input-file path
        (lambda (port)
          (let ((data (read port)))
            (if (list? data) (map alist->co data) '()))))
      '()))

(define* (make-cognitive-memory #:key (path #f) (restore? #t))
  (let ((memory (%make-memory (list (if restore? (load-objects path) '())) path)))
    ;; `/clear` must establish a new durable memory boundary rather than loading
    ;; the preceding session's memories on the next constructor call.
    (when (and path (not restore?))
      (persist! memory))
    memory))

(define (memory-objects memory)
  (car (memory-objects-cell memory)))

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
                                 (co-id successor))))
      (memory-store! memory retired)
      (memory-store! memory successor)
      successor)))

(define (memory-consolidate! memory objects)
  "Persist a verified evidence chain as structured memory, newest object first."
  (for-each (lambda (co)
              (when (and (cognitive-object? co)
                         (or (fact? co)
                             (memq (co-type co) '(evidence result))))
                (memory-store! memory co)))
            objects)
  objects)

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

(define* (memory-retrieve memory goal #:key (limit 5))
  "Return goal-relevant COs, ranked by lexical overlap, then recency/insertion
order. Empty-overlap memories are excluded to prevent transcript-like flooding."
  (let ((scored (filter (lambda (pair) (> (cdr pair) 0))
                        (map (lambda (co) (cons co (overlap-score goal co)))
                             (filter temporally-valid?
                                     (memory-objects memory))))))
    (map car
         (take (sort scored (lambda (left right) (> (cdr left) (cdr right))))
               (min limit (length scored))))))

(define (temporally-valid? co)
  (let ((now (current-time)))
    (and (<= (co-valid-from co) now)
         (not (co-invalidated-by co))
         (or (eq? (co-valid-to co) 'INF)
             (>= (co-valid-to co) now)))))

(define* (memory-retrieve-facts memory goal #:key (limit 3) (minimum-overlap 2))
  "Return accepted facts sufficiently related to GOAL for memory-only answering."
  (let ((scored
         (filter (lambda (pair) (>= (cdr pair) minimum-overlap))
                 (map (lambda (co) (cons co (overlap-score goal co)))
                      (filter (lambda (co) (and (fact? co) (temporally-valid? co)))
                              (memory-objects memory))))))
    (map car
         (take (sort scored (lambda (left right) (> (cdr left) (cdr right))))
               (min limit (length scored))))))

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
