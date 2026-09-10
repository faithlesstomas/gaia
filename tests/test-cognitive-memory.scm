(define-module (tests test-cognitive-memory)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-64)
  #:use-module (ice-9 ftw)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-memory))

(test-begin "gaia-cognitive-memory")

(test-assert "memory persists COs and retrieves only goal-relevant context"
  (let* ((path "/tmp/gaia-gcas-memory-test.scm")
         (_ (when (file-exists? path) (delete-file path)))
         (memory (make-cognitive-memory #:path path))
         (relevant (make-cognitive-object 'evidence "Guile arithmetic evaluation has executable output" #:provenance 'MEMORY))
         (irrelevant (make-cognitive-object 'evidence "Ocean currents are dynamic" #:provenance 'MEMORY)))
    (memory-store! memory relevant)
    (memory-store! memory irrelevant)
    (let ((reloaded (make-cognitive-memory #:path path)))
      (delete-file path)
      (and (= (length (memory-objects reloaded)) 2)
           (equal? (map co-id (memory-retrieve reloaded "Find Guile executable arithmetic output"))
                   (list (co-id relevant)))))))

(test-assert "context reconstruction contains only explicit GCAS sources"
  (let* ((goal (make-cognitive-object 'goal "Verify arithmetic output" #:provenance 'USER))
         (active (make-cognitive-object 'action "(+ 20 22)" #:provenance 'LLM))
         (memory (make-cognitive-object 'evidence "Known arithmetic rule" #:provenance 'MEMORY))
         (context (reconstruct-context goal (list active) (list memory) #:constraints '("Require verification."))))
    (and (string-contains context "Current goal:")
         (string-contains context "Admitted workspace:")
         (string-contains context "Retrieved structured memory:")
         (string-contains context "Require verification."))))

(test-assert "explicit user testimony remains an unverified observation"
  (let* ((memory (make-cognitive-memory))
         (observation (make-user-memory-claim "Mam na imię Tomasz")))
    (memory-store! memory observation)
    (let ((facts (memory-retrieve-facts memory "Jak mam na imię?"))
          (retrieved (memory-retrieve memory "Jak mam na imię?")))
      (and (eq? (co-type observation) 'observation)
           (eq? (co-epistemic-status observation) 'UNKNOWN)
           (eq? (co-verification-status observation) 'UNVERIFIED)
           (null? facts)
           (= (length retrieved) 1)))))

(test-assert "user testimony survives restart without becoming a fact"
  (let* ((path "/tmp/gaia-user-testimony-memory.scm")
         (_ (when (file-exists? path) (delete-file path)))
         (memory (make-cognitive-memory #:path path))
         (testimony (make-user-memory-claim "Mam na imię Tomasz")))
    (memory-consolidate! memory (list testimony)
                         #:reason 'USER_TESTIMONY_RETENTION
                         #:revalidation 'ON_USER_CORRECTION)
    (let* ((restored (make-cognitive-memory #:path path))
           (selected (memory-retrieve restored "Jak mam na imię?")))
      (delete-file path)
      (and (= (length selected) 1)
           (eq? (memory-role (car selected)) 'USER_TESTIMONY)
           (eq? (co-epistemic-status (car selected)) 'UNKNOWN)
           (eq? (co-verification-status (car selected)) 'UNVERIFIED)
           (null? (memory-retrieve-facts restored "Jak mam na imię?"))))))

(test-assert "expired and invalidated facts are excluded from retrieval"
  (let* ((memory (make-cognitive-memory))
         (now (current-time))
         (expired (make-cognitive-object
                   'claim "Guile arithmetic fact expired"
                   #:provenance 'SYMBOLIC_INFERENCE
                   #:epistemic-status 'ACCEPTED
                   #:verification-status 'VERIFIED
                   #:valid-from (- now 20) #:valid-to (- now 10)))
         (invalidated (make-cognitive-object
                       'claim "Guile arithmetic fact invalidated"
                       #:provenance 'SYMBOLIC_INFERENCE
                       #:epistemic-status 'ACCEPTED
                       #:verification-status 'VERIFIED
                       #:invalidated-by "co-refutation")))
    (memory-store! memory expired)
    (memory-store! memory invalidated)
    (null? (memory-retrieve-facts memory "Guile arithmetic fact" #:minimum-overlap 2))))

(test-error "unknown memory roles fail closed"
  #t
  (memory-store!
   (make-cognitive-memory)
   (make-cognitive-object
    'observation "Malformed retained memory"
    #:provenance 'USER
    #:relations '((memory-role . TRANSCRIPT_HISTORY)))))

(test-assert "consolidation assigns roles, retention reason, and revalidation policy"
  (let* ((memory (make-cognitive-memory))
         (claim
          (make-cognitive-object
           'claim "Verified deployment port is 4242"
           #:provenance 'SYMBOLIC_INFERENCE
           #:epistemic-status 'ACCEPTED
           #:verification-status 'VERIFIED))
         (evidence
          (make-cognitive-object
           'evidence "Deployment probe observed port 4242"
           #:provenance 'EXECUTION))
         (procedure
          (make-cognitive-object
           'procedure "Reuse the verified deployment probe"
           #:provenance 'SYMBOLIC_INFERENCE
           #:epistemic-status 'ACCEPTED
           #:verification-status 'VERIFIED))
         (reflection
          (make-cognitive-object
           'reflection "The deployment probe is reliable for local services"
           #:provenance 'SYMBOLIC_INFERENCE))
         (transient-goal
          (make-cognitive-object 'goal "Deploy a service" #:provenance 'USER)))
    (memory-consolidate! memory
                         (list claim evidence procedure reflection transient-goal)
                         #:reason 'VERIFIED_GOAL
                         #:revalidation 'ON_ENVIRONMENT_CHANGE)
    (let ((retained (memory-objects memory)))
      (and (= (length retained) 4)
           (eq? (memory-role (memory-object-by-id memory (co-id claim)))
                'SEMANTIC)
           (eq? (memory-role (memory-object-by-id memory (co-id evidence)))
                'EPISODIC)
           (eq? (memory-role (memory-object-by-id memory (co-id procedure)))
                'PROCEDURAL)
           (eq? (memory-role (memory-object-by-id memory (co-id reflection)))
                'METACOGNITIVE)
           (not (memory-object-by-id memory (co-id transient-goal)))
           (every (lambda (co)
                    (and (eq? (assoc-ref (co-relations co) 'retention-reason)
                              'VERIFIED_GOAL)
                         (eq? (assoc-ref (co-relations co) 'revalidate-on)
                              'ON_ENVIRONMENT_CHANGE)))
                  retained)))))

(test-assert "guarded retrieval expands through graph relations without promoting evidence"
  (let* ((memory (make-cognitive-memory))
         (evidence
          (make-cognitive-object
           'evidence "Artifact checksum 9a7c was independently observed"
           #:provenance 'EXECUTION
           #:relations '((memory-role . EPISODIC))))
         (claim
          (make-cognitive-object
           'claim "The lunar deployment procedure is verified"
           #:provenance 'SYMBOLIC_INFERENCE
           #:epistemic-status 'ACCEPTED
           #:verification-status 'VERIFIED
           #:relations `((supported-by . ,(co-id evidence))
                         (memory-role . SEMANTIC))))
         (transcript-goal
          (make-cognitive-object
           'goal "The lunar deployment procedure is verified"
           #:provenance 'USER)))
    (for-each (lambda (co) (memory-store! memory co))
              (list evidence claim transcript-goal))
    (let ((selected (memory-retrieve memory "lunar deployment procedure"
                                     #:limit 3 #:depth 1)))
      (and (member (co-id claim) (map co-id selected))
           (member (co-id evidence) (map co-id selected))
           (not (member (co-id transcript-goal) (map co-id selected)))
           (eq? (co-epistemic-status evidence) 'UNKNOWN)
           (eq? (co-verification-status evidence) 'UNVERIFIED)))))

(test-assert "STI activation is bounded, rebuildable, and epistemically neutral"
  (let* ((memory (make-cognitive-memory #:active-limit 2))
         (first (make-cognitive-object 'evidence "first" #:provenance 'EXECUTION))
         (second (make-cognitive-object 'evidence "second" #:provenance 'EXECUTION))
         (third (make-cognitive-object 'evidence "third" #:provenance 'EXECUTION)))
    (for-each (lambda (co) (memory-store! memory co))
              (list first second third))
    (memory-activate! memory (list (co-id first)) #:amount 2)
    (memory-activate! memory (list (co-id second)) #:amount 1)
    (memory-activate! memory (list (co-id third)) #:amount 3)
    (and (> (memory-activation memory (co-id first)) 0)
         (= (memory-activation memory (co-id second)) 0)
         (> (memory-activation memory (co-id third)) 0)
         (eq? (co-epistemic-status first) 'UNKNOWN)
         (eq? (co-verification-status first) 'UNVERIFIED))))

(test-end "gaia-cognitive-memory")
