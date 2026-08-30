(define-module (tests test-capability-registry)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-64)
  #:use-module (gaia capability-registry)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-state))

(test-begin "gaia-capability-registry")

(define goal
  (make-cognitive-object 'goal "Verify fixture" #:provenance 'USER))
(define action
  (make-cognitive-object 'action "(+ 40 2)" #:provenance 'LLM))
(define result
  (make-cognitive-object 'result "42" #:provenance 'REPL))
(define evidence
  (make-cognitive-object 'evidence "Observed 42" #:provenance 'EXECUTION))
(define execution-claim
  (make-cognitive-object
   'claim "The action returned 42"
   #:provenance 'SYMBOLIC_INFERENCE
   #:epistemic-status 'ACCEPTED
   #:verification-status 'VERIFIED))
(define state (make-cognitive-state))

(define (verify contract custom-result custom-evidence)
  (let ((manifest
         (make-capability-manifest
          'fixture "1" "Fixture capability" (lambda (task) #t)
          "Fixture criterion" "Fixture action schema" contract)))
    (registry-verify manifest goal action custom-result custom-evidence
                     execution-claim state)))

(test-assert "default registry advertises five unambiguous executable capabilities"
  (let* ((registry (make-default-capability-registry))
         (manifests (registry-manifests registry))
         (factorial (registry-match registry "Define factorial and compute 6"))
         (unknown (registry-match registry "Send an email")))
    (and (= (length manifests) 5)
         (every capability-manifest-advertised? manifests)
         (= (length (delete-duplicates
                     (map capability-manifest-id manifests)))
            5)
         (eq? (capability-manifest-id factorial) 'factorial-6)
         (every (lambda (manifest)
                  (and (string=? (capability-manifest-version manifest) "2")
                       (procedure?
                        (capability-manifest-private-harness manifest))))
                manifests)
         (eq? (verifier-contract-class
               (capability-manifest-verifier factorial))
              'UNIT_TEST)
         (not unknown))))

(test-assert "production harness is private and expands after repair"
  (let* ((manifest
          (registry-match (make-default-capability-registry)
                          "Return the first ten Fibonacci terms"))
         (action
          "(define (fibonacci-sequence n) '(0 1 1 2 3 5 8 13 21 34))")
         (first (capability-manifest-prepare-action manifest action 1))
         (repair (capability-manifest-prepare-action manifest action 2)))
    (and (string-prefix? action first)
         (string-prefix? action repair)
         (string-contains first "gaia-private-checks")
         (> (string-length repair) (string-length first))
         (not (string-contains
               (capability-manifest-action-schema manifest)
               "fibonacci-sequence 12")))))

(test-assert "exact and structured datum verifiers consume executed Results"
  (let* ((exact (make-datum-verifier 'exact-42 42))
         (structured
          (make-datum-verifier 'structured-list '(1 4 9)
                               #:class 'STRUCTURED_VALUE))
         (list-result
          (make-cognitive-object 'result "(1 4 9)" #:provenance 'REPL)))
    (and (eq? (capability-verification-status
               (verify exact result evidence))
              'SATISFIED)
         (eq? (capability-verification-status
               (verify exact list-result evidence))
              'REJECTED)
         (eq? (capability-verification-status
               (verify structured list-result evidence))
              'SATISFIED))))

(test-assert "predicate and unit-test verifier classes are reusable"
  (let* ((predicate
          (make-predicate-verifier 'positive even? "The Result is even."))
         (unit (make-unit-test-verifier 'unit-summary #:minimum-passed 2))
         (unit-result
          (make-cognitive-object
           'result "((passed . 3) (failed . 0))" #:provenance 'REPL))
         (failed-result
          (make-cognitive-object
           'result "((passed . 2) (failed . 1))" #:provenance 'REPL)))
    (and (eq? (capability-verification-status
               (verify predicate result evidence))
              'SATISFIED)
         (eq? (capability-verification-status
               (verify unit unit-result evidence))
              'SATISFIED)
         (eq? (capability-verification-status
               (verify unit failed-result evidence))
              'REJECTED))))

(test-assert "artifact, environment, and human approval verifiers require scoped evidence"
  (let* ((artifact (make-artifact-verifier 'artifact "sha256:abc"))
         (environment
          (make-environment-state-verifier 'environment '(service . ready)))
         (approval (make-human-approval-verifier 'approval 'publish-report))
         (artifact-evidence
          (make-cognitive-object
           'evidence "Artifact observed" #:provenance 'EXECUTION
           #:relations '((artifact-hash . "sha256:abc"))))
         (environment-evidence
          (make-cognitive-object
           'evidence "Service observed" #:provenance 'EXECUTION
           #:relations '((environment-state . (service . ready)))))
         (approval-evidence
          (make-cognitive-object
           'evidence "User approved exact publication" #:provenance 'USER
           #:relations '((approved-scope . publish-report)
                         (approved-by . "user-1"))))
         (unscoped-approval
          (make-cognitive-object
           'evidence "Generic approval" #:provenance 'USER)))
    (and (eq? (capability-verification-status
               (verify artifact result artifact-evidence))
              'SATISFIED)
         (eq? (capability-verification-status
               (verify environment result environment-evidence))
              'SATISFIED)
         (eq? (capability-verification-status
               (verify approval result approval-evidence))
              'SATISFIED)
         (eq? (capability-verification-status
               (verify approval result unscoped-approval))
              'INCONCLUSIVE))))

(test-error "ambiguous advertised capability selection fails closed"
  #t
  (let* ((registry (make-capability-registry))
         (verifier (make-datum-verifier 'same 1)))
    (registry-register!
     registry
     (make-capability-manifest
      'one "1" "One" (lambda (task) #t) "criterion" "schema" verifier))
    (registry-register!
     registry
     (make-capability-manifest
      'two "1" "Two" (lambda (task) #t) "criterion" "schema" verifier))
    (registry-match registry "ambiguous")))

(test-end "gaia-capability-registry")
