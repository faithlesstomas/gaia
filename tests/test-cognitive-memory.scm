(define-module (tests test-cognitive-memory)
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

(test-end "gaia-cognitive-memory")
