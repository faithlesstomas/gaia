(define-module (tests test-cognitive-memory-graph)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-64)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-memory)
  #:use-module (gaia cognitive-process)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia cognitive-state)
  #:use-module (gaia production-processors))

(test-begin "gaia-cognitive-memory-graph")

(define (with-clean-memory path thunk)
  (when (file-exists? path) (delete-file path))
  (dynamic-wind
    (lambda () #t)
    thunk
    (lambda ()
      (when (file-exists? path) (delete-file path)))))

(test-assert "verified graph memory survives restart and reconstructs a new Goal context"
  (with-clean-memory
   "/tmp/gaia-memory-graph-restart.scm"
   (lambda ()
     (let* ((path "/tmp/gaia-memory-graph-restart.scm")
            (first-session (make-cognitive-session #:memory-path path))
            (evidence
             (make-cognitive-object
              'evidence "Observed GAIA service port: 4242"
              #:provenance 'EXECUTION
              #:epistemic-status 'ACCEPTED
              #:verification-status 'VERIFIED
              #:relations '((memory-role . EPISODIC))))
            (claim
             (make-cognitive-object
              'claim "The verified GAIA service port is 4242"
              #:provenance 'SYMBOLIC_INFERENCE
              #:epistemic-status 'ACCEPTED
              #:verification-status 'VERIFIED
              #:relations `((supported-by . ,(co-id evidence))
                            (memory-role . SEMANTIC)))))
       (memory-consolidate! (session-memory first-session)
                            (list evidence claim))
       ;; Repeating an existing edge must not duplicate graph state.
       (memory-link! (session-memory first-session)
                     (co-id claim) 'supported-by (co-id evidence))
       (memory-link! (session-memory first-session)
                     (co-id claim) 'supported-by (co-id evidence))
       ;; Constructing a new session is the restart boundary. No transcript is
       ;; supplied or replayed; only the durable Cognitive Memory is restored.
       (let* ((second-session (make-cognitive-session #:memory-path path
                                                      #:workspace-capacity 3))
              (restored-memory (session-memory second-session))
              (generated-prompt-cell (list #f))
              (goal
               (make-cognitive-object
                'goal "Which verified GAIA service port is configured?"
                #:provenance 'USER))
              (selected
               (memory-retrieve-facts
                restored-memory (co-content goal) #:minimum-overlap 2))
              (support
               (memory-related restored-memory (co-id claim)
                               #:relation-type 'supported-by))
              (supported-claims
               (memory-related restored-memory (co-id evidence)
                               #:relation-type 'supported-by
                               #:direction 'incoming))
              (context (reconstruct-context goal '() selected))
              (process
               (start-production-process!
                second-session (co-content goal)
                #:generate
                (lambda (prompt succeed fail)
                  (set-car! generated-prompt-cell prompt)
                  (succeed "No new executable Action is required."))
                #:extract-action (lambda (response) #f)
                #:execute
                (lambda args
                  (error "restored memory retrieval must not execute"))))
              (memory-satisfaction-claims
               (filter
                (lambda (co)
                  (and (eq? (co-type co) 'claim)
                       (eq? (co-provenance co) 'MEMORY)
                       (assoc-ref (co-relations co) 'satisfies)))
                (state-objects (session-state second-session))))
              (event-types
               (map event-type
                    (state-events (session-state second-session)))))
         (and (= (length selected) 1)
              (equal? (co-id (car selected)) (co-id claim))
              (= (length support) 1)
              (equal? (co-id (car support)) (co-id evidence))
              (= (length supported-claims) 1)
              (equal? (co-id (car supported-claims)) (co-id claim))
              (string-contains context "The verified GAIA service port is 4242")
              (not (process-active? process))
              (eq? (process-outcome process) 'INSUFFICIENT_INFORMATION)
              (null? memory-satisfaction-claims)
              (not (memq 'GoalCompleted event-types))
              (string-contains (car generated-prompt-cell)
                               "The verified GAIA service port is 4242")
              (not (string-contains (car generated-prompt-cell)
                                    "conversation transcript"))))))))

(test-assert "invalidation propagates through justification dependencies"
  (let* ((memory (make-cognitive-memory))
         (premise
          (make-cognitive-object
           'claim "The active GAIA service port is 4242"
           #:provenance 'SYMBOLIC_INFERENCE
           #:epistemic-status 'ACCEPTED
           #:verification-status 'VERIFIED))
         (dependent
          (make-cognitive-object
           'claim "The GAIA health URL uses port 4242"
           #:provenance 'SYMBOLIC_INFERENCE
           #:epistemic-status 'ACCEPTED
           #:verification-status 'VERIFIED
           #:relations `((derived-from . ,(co-id premise)))))
         (transitive-dependent
          (make-cognitive-object
           'claim "The monitoring probe targets the GAIA health URL"
           #:provenance 'SYMBOLIC_INFERENCE
           #:epistemic-status 'ACCEPTED
           #:verification-status 'VERIFIED
           #:relations `((derived-from . ,(co-id dependent)))))
         (conflict
          (make-cognitive-object
           'conflict "A fresh observation reports service port 4343"
           #:provenance 'EXECUTION)))
    (for-each (lambda (co) (memory-store! memory co))
              (list premise dependent transitive-dependent conflict))
    (memory-invalidate! memory (co-id premise) (co-id conflict))
    (let ((invalidated-premise
           (memory-object-by-id memory (co-id premise)))
          (invalidated-dependent
           (memory-object-by-id memory (co-id dependent)))
          (invalidated-transitive-dependent
           (memory-object-by-id memory (co-id transitive-dependent)))
          (invalidated-targets
           (memory-related memory (co-id conflict)
                           #:relation-type 'invalidates)))
      (and (equal? (co-invalidated-by invalidated-premise) (co-id conflict))
           (equal? (co-invalidated-by invalidated-dependent) (co-id conflict))
           (equal? (co-invalidated-by invalidated-transitive-dependent)
                   (co-id conflict))
           (not (fact? invalidated-premise))
           (not (fact? invalidated-dependent))
           (not (fact? invalidated-transitive-dependent))
           (= (length invalidated-targets) 1)
           (null? (memory-retrieve-facts memory "GAIA service port 4242"
                                         #:minimum-overlap 2))))))

(test-assert "supersession survives restart and promotes a new semantic version"
  (with-clean-memory
   "/tmp/gaia-memory-graph-supersession.scm"
   (lambda ()
     (let* ((path "/tmp/gaia-memory-graph-supersession.scm")
            (memory (make-cognitive-memory #:path path))
            (old
             (make-cognitive-object
              'claim "GAIA service port is 4242"
              #:provenance 'SYMBOLIC_INFERENCE
              #:epistemic-status 'ACCEPTED
              #:verification-status 'VERIFIED))
            (new
             (make-cognitive-object
              'claim "GAIA service port is 4343"
              #:provenance 'SYMBOLIC_INFERENCE
              #:epistemic-status 'ACCEPTED
              #:verification-status 'VERIFIED)))
       (memory-store! memory old)
       (let* ((successor (memory-supersede! memory (co-id old) new))
              (reloaded (make-cognitive-memory #:path path))
              (retired (memory-object-by-id reloaded (co-id old)))
              (restored-successor
               (memory-object-by-id reloaded (co-id successor)))
              (predecessors
               (memory-related reloaded (co-id successor)
                               #:relation-type 'supersedes)))
         (and (= (length (memory-objects reloaded)) 2)
              (equal? (co-invalidated-by retired) (co-id successor))
              (not (fact? retired))
              (fact? restored-successor)
              (= (length predecessors) 1)
              (equal? (co-id (car predecessors)) (co-id retired))))))))

(test-end "gaia-cognitive-memory-graph")
