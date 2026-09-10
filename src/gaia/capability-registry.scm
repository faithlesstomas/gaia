(define-module (gaia capability-registry)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (gaia com)
  #:export (<capability-verification>
            capability-verification?
            capability-verification-status
            capability-verification-rationale
            capability-verification-claim-content
            <verifier-contract>
            verifier-contract?
            verifier-contract-id
            verifier-contract-class
            make-verifier-contract
            make-datum-verifier
            make-predicate-verifier
            make-unit-test-verifier
            make-artifact-verifier
            make-environment-state-verifier
            make-human-approval-verifier
            <capability-manifest>
            capability-manifest?
            capability-manifest-id
            capability-manifest-version
            capability-manifest-description
            capability-manifest-completion-criteria
            capability-manifest-action-schema
            capability-manifest-verifier
            capability-manifest-private-harness
            capability-manifest-prepare-action
            capability-manifest-advertised?
            make-capability-manifest
            <capability-registry>
            capability-registry?
            make-capability-registry
            registry-manifests
            registry-register!
            registry-match
            registry-verify
            make-default-capability-registry
            VALID-VERIFIER-CLASSES))

;; A verifier contract is independent from model generation and execution. It
;; consumes only explicit GCAS records and returns a typed decision that the
;; Goal Verifier adapts into the process-level verdict.
(define VALID-VERIFIER-CLASSES
  '(EXACT_VALUE STRUCTURED_VALUE PREDICATE_PROPERTY UNIT_TEST ARTIFACT
                ENVIRONMENT_STATE HUMAN_APPROVAL))

(define-record-type <capability-verification>
  (%make-capability-verification status rationale claim-content)
  capability-verification?
  (status capability-verification-status)
  (rationale capability-verification-rationale)
  (claim-content capability-verification-claim-content))

(define (make-capability-verification status rationale claim-content)
  (unless (and (memq status '(SATISFIED REJECTED INCONCLUSIVE))
               (string? rationale) (> (string-length rationale) 0)
               (string? claim-content))
    (error "Invalid capability verification" status rationale claim-content))
  (%make-capability-verification status rationale claim-content))

(define-record-type <verifier-contract>
  (%make-verifier-contract id class evaluator)
  verifier-contract?
  (id verifier-contract-id)
  (class verifier-contract-class)
  (evaluator verifier-contract-evaluator))

(define (make-verifier-contract id class evaluator)
  (unless (and (symbol? id) (memq class VALID-VERIFIER-CLASSES)
               (procedure? evaluator))
    (error "Invalid verifier contract" id class evaluator))
  (%make-verifier-contract id class evaluator))

(define (read-single-datum text)
  (catch #t
    (lambda ()
      (call-with-input-string text
        (lambda (port)
          (let ((value (read port)) (tail (read port)))
            (and (not (eof-object? value))
                 (eof-object? tail)
                 (cons #t value))))))
    (lambda _ #f)))

(define (read-all-datums text)
  (catch #t
    (lambda ()
      (call-with-input-string text
        (lambda (port)
          (let loop ((forms '()))
            (let ((form (read port)))
              (if (eof-object? form)
                  (reverse forms)
                  (loop (cons form forms))))))))
    (lambda _ #f)))

(define (form-defines-binding? form binding)
  (match form
    (('define (name . args) . body) (eq? name binding))
    (('define name value) (eq? name binding))
    (('begin . forms)
     (any (lambda (nested) (form-defines-binding? nested binding)) forms))
    (_ #f)))

(define (action-defines-binding? action binding)
  (let ((forms (read-all-datums (co-content action))))
    (and forms (any (lambda (form) (form-defines-binding? form binding)) forms))))

(define* (make-datum-verifier id expected
                              #:key
                              required-binding
                              (class 'EXACT_VALUE))
  (unless (memq class '(EXACT_VALUE STRUCTURED_VALUE))
    (error "Datum verifier class must be exact or structured" class))
  (make-verifier-contract
   id class
   (lambda (goal action result evidence execution-claim state)
     (let* ((parsed (read-single-datum (co-content result)))
            (binding-ok?
             (or (not required-binding)
                 (action-defines-binding? action required-binding)))
            (value-ok? (and parsed (equal? (cdr parsed) expected))))
       (if (and binding-ok? value-ok?)
           (make-capability-verification
            'SATISFIED
            "The independent datum verifier accepted the executed Result."
            (if required-binding
                (string-append
                 "Verified Scheme implementation:\n```scheme\n"
                 (co-content action)
                 "\n```\nObserved result: " (format #f "~s" expected) ".")
                (format #f "Verified result: ~s" expected)))
           (make-capability-verification
            'REJECTED
            (string-append
             (if binding-ok? "" "The required procedure definition was not observed. ")
             (format #f "Expected final datum ~s, observed ~s."
                     expected (and parsed (cdr parsed))))
            ""))))))

(define (make-predicate-verifier id predicate description)
  (unless (and (procedure? predicate) (string? description))
    (error "Invalid predicate verifier" id predicate description))
  (make-verifier-contract
   id 'PREDICATE_PROPERTY
   (lambda (goal action result evidence execution-claim state)
     (let ((parsed (read-single-datum (co-content result))))
       (if (and parsed (predicate (cdr parsed)))
           (make-capability-verification
            'SATISFIED description
            (format #f "Verified property for result: ~s" (cdr parsed)))
           (make-capability-verification
            'REJECTED
            (string-append "The independent property verifier rejected the Result: "
                           description)
            ""))))))

(define (unit-test-summary value)
  (and (list? value)
       (let ((passed (assoc-ref value 'passed))
             (failed (assoc-ref value 'failed)))
         (and (integer? passed) (>= passed 0)
              (integer? failed) (>= failed 0)
              (cons passed failed)))))

(define* (make-unit-test-verifier id
                                  #:key
                                  (minimum-passed 1)
                                  (required-binding #f))
  (make-verifier-contract
   id 'UNIT_TEST
   (lambda (goal action result evidence execution-claim state)
     (let* ((binding-ok?
             (or (not required-binding)
                 (action-defines-binding? action required-binding)))
            (parsed (read-single-datum (co-content result)))
            (summary (and parsed (unit-test-summary (cdr parsed)))))
       (if (and binding-ok? summary
                (>= (car summary) minimum-passed) (= (cdr summary) 0))
           (make-capability-verification
            'SATISFIED
            "The private behavioral test summary reports no failures."
            (format #f "Verified hidden behavioral tests: ~a passed, zero failed."
                    (car summary)))
           (make-capability-verification
            'REJECTED
            (string-append
             (if binding-ok? "" "The required procedure definition was not observed. ")
             "Private tests were missing, insufficient, or reported failures.")
            ""))))))

(define (make-artifact-verifier id expected-hash)
  (make-verifier-contract
   id 'ARTIFACT
   (lambda (goal action result evidence execution-claim state)
     (let ((observed (assoc-ref (co-relations evidence) 'artifact-hash)))
       (if (and (string? observed) (string=? observed expected-hash))
           (make-capability-verification
            'SATISFIED "The independently observed artifact hash matches."
            (string-append "Verified artifact hash: " expected-hash))
           (make-capability-verification
            'REJECTED "The required artifact hash was not independently observed." ""))))))

(define (make-environment-state-verifier id expected-state)
  (make-verifier-contract
   id 'ENVIRONMENT_STATE
   (lambda (goal action result evidence execution-claim state)
     (let ((observed (assoc-ref (co-relations evidence) 'environment-state)))
       (if (equal? observed expected-state)
           (make-capability-verification
            'SATISFIED "Fresh environment observation matches the Goal contract."
            (format #f "Verified environment state: ~s" expected-state))
           (make-capability-verification
            'REJECTED "Fresh environment state does not match the Goal contract." ""))))))

(define (make-human-approval-verifier id required-scope)
  (make-verifier-contract
   id 'HUMAN_APPROVAL
   (lambda (goal action result evidence execution-claim state)
     (let ((scope (assoc-ref (co-relations evidence) 'approved-scope))
           (approver (assoc-ref (co-relations evidence) 'approved-by)))
       (if (and (equal? scope required-scope) approver
                (eq? (co-provenance evidence) 'USER))
           (make-capability-verification
            'SATISFIED "A scoped user approval record matches the exact request."
            (format #f "Verified human approval for scope: ~s" required-scope))
           (make-capability-verification
            'INCONCLUSIVE "No matching scoped human approval record is available." ""))))))

(define-record-type <capability-manifest>
  (%make-capability-manifest id version description intent-matcher
                             completion-criteria action-schema verifier
                             private-harness advertised?)
  capability-manifest?
  (id capability-manifest-id)
  (version capability-manifest-version)
  (description capability-manifest-description)
  (intent-matcher capability-manifest-intent-matcher)
  (completion-criteria capability-manifest-completion-criteria)
  (action-schema capability-manifest-action-schema)
  (verifier capability-manifest-verifier)
  (private-harness capability-manifest-private-harness)
  (advertised? capability-manifest-advertised?))

(define* (make-capability-manifest id version description intent-matcher
                                   completion-criteria action-schema verifier
                                   #:key
                                   (private-harness #f)
                                   (advertised? #t))
  (unless (and (symbol? id) (string? version) (string? description)
               (procedure? intent-matcher) (string? completion-criteria)
               (string? action-schema) (verifier-contract? verifier)
               (or (not private-harness) (procedure? private-harness))
               (boolean? advertised?))
    (error "Invalid capability manifest" id version))
  (%make-capability-manifest id version description intent-matcher
                             completion-criteria action-schema verifier private-harness
                             advertised?))

(define (capability-manifest-prepare-action manifest action attempt)
  "Append a manifest's private harness at the execution boundary.

The returned code is runtime-only: it must never be projected into model
generation or repair context.  ATTEMPT lets a repaired Action receive a larger
fresh holdout suite."
  (unless (and (capability-manifest? manifest) (string? action)
               (integer? attempt) (> attempt 0))
    (error "Invalid private capability execution" manifest action attempt))
  (let ((harness (capability-manifest-private-harness manifest)))
    (if harness (string-append action (harness attempt)) action)))

(define-record-type <capability-registry>
  (%make-capability-registry manifests-cell)
  capability-registry?
  (manifests-cell registry-manifests-cell))

(define (make-capability-registry)
  (%make-capability-registry (list '())))

(define (registry-manifests registry)
  (car (registry-manifests-cell registry)))

(define (registry-register! registry manifest)
  (unless (and (capability-registry? registry) (capability-manifest? manifest))
    (error "Registry accepts capability manifests" registry manifest))
  (when (find (lambda (existing)
                (eq? (capability-manifest-id existing)
                     (capability-manifest-id manifest)))
              (registry-manifests registry))
    (error "Duplicate capability manifest" (capability-manifest-id manifest)))
  (set-car! (registry-manifests-cell registry)
            (append (registry-manifests registry) (list manifest)))
  manifest)

(define (registry-match registry task)
  "Return the single advertised capability matching TASK, or #f.

Overlapping advertised matchers fail closed because capability selection would
otherwise be ambiguous."
  (let ((matches
         (filter (lambda (manifest)
                   (and (capability-manifest-advertised? manifest)
                        ((capability-manifest-intent-matcher manifest) task)))
                 (registry-manifests registry))))
    (cond
     ((null? matches) #f)
     ((null? (cdr matches)) (car matches))
     (else (error "Ambiguous advertised capability" task
                  (map capability-manifest-id matches))))))

(define (registry-verify manifest goal action result evidence execution-claim state)
  (unless (capability-manifest? manifest)
    (error "Capability verification requires a manifest" manifest))
  ((verifier-contract-evaluator (capability-manifest-verifier manifest))
   goal action result evidence execution-claim state))

(define (contains-all? text markers)
  (let ((normalized (string-downcase (format #f "~a" text))))
    (every (lambda (marker) (string-contains normalized marker)) markers)))

(define (datum-criteria expected . optional-binding)
  (string-append
   (if (null? optional-binding)
       ""
       (format #f "Define procedure ~a. " (car optional-binding)))
   (format #f "The final Scheme value must equal ~s. " expected)
   "An independent deterministic verifier must accept the executed Result."))

(define (rotate values offset)
  (let* ((size (length values))
         (split (if (= size 0) 0 (modulo offset size))))
    (append (drop values split) (take values split))))

(define (select-production-probes bank attempt)
  (let* ((base (take (rotate bank (- attempt 1))
                     (min 4 (length bank))))
         (holdout (take (rotate bank (+ attempt 4))
                        (min 2 (length bank)))))
    (if (> attempt 1)
        (delete-duplicates (append base holdout) equal?)
        base)))

(define (make-private-harness probe-bank)
  (lambda (attempt)
    (let* ((probes (select-production-probes probe-bank attempt))
           (checks
            (map (lambda (probe)
                   `(equal? ,(car probe) ',(cadr probe)))
                 probes)))
      (format #f
              "\n(let* ((gaia-private-checks (list ~{~s~^ ~}))\n       (gaia-private-passed\n        (let loop ((rest gaia-private-checks) (count 0))\n          (if (null? rest) count\n              (loop (cdr rest)\n                    (if (car rest) (+ count 1) count)))))\n       (gaia-private-total (length gaia-private-checks)))\n  `((passed . ,gaia-private-passed)\n    (failed . ,(- gaia-private-total gaia-private-passed))))"
              checks))))

(define (register-behavior-capability! registry id description markers binding
                                       probe-bank)
  (let* ((verifier
          (make-unit-test-verifier
           (string->symbol (string-append (symbol->string id) "-verifier-v2"))
           #:minimum-passed 4 #:required-binding binding))
         (criteria
          (format #f
                  "Define procedure ~a. It must satisfy the declared behavior for independently selected inputs. A private deterministic test suite must accept the executed implementation."
                  binding)))
    (registry-register!
     registry
     (make-capability-manifest
      id "2" description
      (if (procedure? markers)
          markers
          (lambda (task) (contains-all? task markers)))
      criteria
      (format #f
              "One complete Guile Action defining ~a for arbitrary contract-valid inputs. Do not call it only for the example input; GAIA executes private tests."
              binding)
      verifier
      #:private-harness (make-private-harness probe-bank)))))

(define (make-default-capability-registry)
  "Return the narrow capability set GAIA currently advertises and evaluates."
  (let ((registry (make-capability-registry)))
    (register-behavior-capability!
     registry 'arithmetic-42 "Arithmetic relation over numeric inputs"
     '("17" "3" "9") 'solve-arithmetic
     '(((solve-arithmetic 0 0 0) 0)
       ((solve-arithmetic 2 3 1) 5)
       ((solve-arithmetic -4 5 3) -23)
       ((solve-arithmetic 9 -2 -7) -11)
       ((solve-arithmetic 10 10 99) 1)
       ((solve-arithmetic 3 7 0) 21)
       ((solve-arithmetic -2 -8 5) 11)))
    (register-behavior-capability!
     registry 'map-squares "Square arbitrary numeric lists"
     '("square" "1 2 3 4 5") 'square-all
     '(((square-all ()) ())
       ((square-all '(0)) (0))
       ((square-all '(-3 2)) (9 4))
       ((square-all '(6 -1 4)) (36 1 16))
       ((square-all '(10 11)) (100 121))
       ((square-all '(-5 -2 0 3)) (25 4 0 9))))
    (register-behavior-capability!
     registry 'filter-evens "Filter even integers from arbitrary lists"
     '("even" "1 2 3 4 5 6 7 8 9 10") 'keep-evens
     '(((keep-evens ()) ())
       ((keep-evens '(1 3 5)) ())
       ((keep-evens '(-4 -3 -2 -1)) (-4 -2))
       ((keep-evens '(2 2 7 8)) (2 2 8))
       ((keep-evens '(0 11 12 15 18)) (0 12 18))
       ((keep-evens '(21 22 24)) (22 24))))
    (register-behavior-capability!
     registry 'factorial-6 "Factorial for non-negative integers"
     '("factorial" "6") 'factorial
     '(((factorial 0) 1)
       ((factorial 1) 1)
       ((factorial 3) 6)
       ((factorial 5) 120)
       ((factorial 7) 5040)
       ((factorial 8) 40320)))
    (register-behavior-capability!
     registry 'fibonacci-10 "Verified Fibonacci procedure"
     (lambda (task)
       (let ((normalized (string-downcase (format #f "~a" task))))
         (or (string-contains normalized "fibonacci")
             (string-contains normalized "fibonacciego"))))
     'fibonacci-sequence
     '(((fibonacci-sequence 0) ())
       ((fibonacci-sequence 1) (0))
       ((fibonacci-sequence 2) (0 1))
       ((fibonacci-sequence 5) (0 1 1 2 3))
       ((fibonacci-sequence 8) (0 1 1 2 3 5 8 13))
       ((fibonacci-sequence 12) (0 1 1 2 3 5 8 13 21 34 55 89))))
    registry))
