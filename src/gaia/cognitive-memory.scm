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
            memory-retrieve
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

(define (tokenize text)
  (filter (lambda (token) (> (string-length token) 1))
          (string-tokenize (string-downcase (format #f "~a" text)))))

(define (overlap-score query candidate)
  (length (lset-intersection string=? (tokenize query) (tokenize (co-content candidate)))))

(define* (memory-retrieve memory goal #:key (limit 5))
  "Return goal-relevant COs, ranked by lexical overlap, then recency/insertion
order. Empty-overlap memories are excluded to prevent transcript-like flooding."
  (let ((scored (filter (lambda (pair) (> (cdr pair) 0))
                        (map (lambda (co) (cons co (overlap-score goal co)))
                             (memory-objects memory)))))
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
