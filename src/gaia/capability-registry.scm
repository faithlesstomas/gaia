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

(define* (make-unit-test-verifier id #:key (minimum-passed 1))
  (make-verifier-contract
   id 'UNIT_TEST
   (lambda (goal action result evidence execution-claim state)
     (let* ((parsed (read-single-datum (co-content result)))
            (summary (and parsed (unit-test-summary (cdr parsed)))))
       (if (and summary (>= (car summary) minimum-passed) (= (cdr summary) 0))
           (make-capability-verification
            'SATISFIED "The independent unit-test summary reports no failures."
            (format #f "Verified unit tests: ~a passed, zero failed."
                    (car summary)))
           (make-capability-verification
            'REJECTED "Unit tests were missing, insufficient, or reported failures." ""))))))

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
                             advertised?)
  capability-manifest?
  (id capability-manifest-id)
  (version capability-manifest-version)
  (description capability-manifest-description)
  (intent-matcher capability-manifest-intent-matcher)
  (completion-criteria capability-manifest-completion-criteria)
  (action-schema capability-manifest-action-schema)
  (verifier capability-manifest-verifier)
  (advertised? capability-manifest-advertised?))

(define* (make-capability-manifest id version description intent-matcher
                                   completion-criteria action-schema verifier
                                   #:key (advertised? #t))
  (unless (and (symbol? id) (string? version) (string? description)
               (procedure? intent-matcher) (string? completion-criteria)
               (string? action-schema) (verifier-contract? verifier)
               (boolean? advertised?))
    (error "Invalid capability manifest" id version))
  (%make-capability-manifest id version description intent-matcher
                             completion-criteria action-schema verifier
                             advertised?))

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

(define (register-datum-capability! registry id description markers expected
                                    class . optional-binding)
  (let* ((binding (and (pair? optional-binding) (car optional-binding)))
         (verifier (make-datum-verifier
                    (string->symbol (string-append (symbol->string id)
                                                   "-verifier"))
                    expected
                    #:required-binding binding #:class class))
         (criteria (if binding
                       (datum-criteria expected binding)
                       (datum-criteria expected))))
    (registry-register!
     registry
     (make-capability-manifest
      id "1" description
      (if (procedure? markers)
          markers
          (lambda (task) (contains-all? task markers)))
      criteria
      "One complete Guile Action whose final expression returns the required datum."
      verifier))))

(define (make-default-capability-registry)
  "Return the narrow capability set GAIA currently advertises and evaluates."
  (let ((registry (make-capability-registry)))
    (register-datum-capability!
     registry 'arithmetic-42 "Exact arithmetic datum" '("17" "3" "9")
     42 'EXACT_VALUE)
    (register-datum-capability!
     registry 'map-squares "Structured list transformation" '("square" "1 2 3 4 5")
     '(1 4 9 16 25) 'STRUCTURED_VALUE)
    (register-datum-capability!
     registry 'filter-evens "Structured list filtering" '("even" "1 2 3 4 5 6 7 8 9 10")
     '(2 4 6 8 10) 'STRUCTURED_VALUE)
    (register-datum-capability!
     registry 'factorial-6 "Verified recursive factorial procedure" '("factorial" "6")
     720 'EXACT_VALUE 'factorial)
    (register-datum-capability!
     registry 'fibonacci-10 "Verified Fibonacci procedure"
     (lambda (task)
       (let ((normalized (string-downcase (format #f "~a" task))))
         (or (string-contains normalized "fibonacci")
             (string-contains normalized "fibonacciego"))))
     '(0 1 1 2 3 5 8 13 21 34) 'STRUCTURED_VALUE 'fibonacci-sequence)
    registry))
