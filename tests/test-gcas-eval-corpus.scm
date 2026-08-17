(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (ice-9 match)
             (srfi srfi-1)
             (gaia com)
             (gaia cognitive-bus)
             (gaia cognitive-process)
             (gaia cognitive-session)
             (gaia cognitive-state)
             (gaia goal-verifier)
             (gaia production-processors))

;; A deterministic, model-free competence corpus for the production GCAS
;; process.  Fixtures describe model proposals, extracted Actions, sandbox
;; outcomes, and the independent acceptance oracle.  The runner measures the
;; same lifecycle for every case instead of embedding one-off control flow in
;; individual unit tests.

(define* (fixture id category responses actions executions expected-outcome
                  expected-generations expected-executions
                  #:key
                  (accepted-results #f)
                  (completion-criteria "Satisfy the deterministic fixture oracle.")
                  (max-transitions 32)
                  (max-stalled-transitions 8)
                  (max-failures 3)
                  (max-replans 3)
                  (repair-target? #f)
                  (mode 'normal)
                  (invoke-late-callback? #f))
  `((id . ,id)
    (category . ,category)
    (responses . ,responses)
    (actions . ,actions)
    (executions . ,executions)
    (expected-outcome . ,expected-outcome)
    (expected-generations . ,expected-generations)
    (expected-executions . ,expected-executions)
    (accepted-results . ,accepted-results)
    (completion-criteria . ,completion-criteria)
    (max-transitions . ,max-transitions)
    (max-stalled-transitions . ,max-stalled-transitions)
    (max-failures . ,max-failures)
    (max-replans . ,max-replans)
    (repair-target? . ,repair-target?)
    (mode . ,mode)
    (invoke-late-callback? . ,invoke-late-callback?)))

(define corpus
  (list
   (fixture 'exact-value-first-pass 'first-pass
            '("exact-good") '(("exact-good" . "(exact-good)"))
            '(("(exact-good)" (ok "42"))) 'COMPLETED 1 1
            #:accepted-results '("42"))
   (fixture 'list-value-first-pass 'first-pass
            '("list-good") '(("list-good" . "(list-good)"))
            '(("(list-good)" (ok "(a b c)"))) 'COMPLETED 1 1
            #:accepted-results '("(a b c)"))
   (fixture 'predicate-first-pass 'first-pass
            '("predicate-good") '(("predicate-good" . "(predicate-good)"))
            '(("(predicate-good)" (ok "even:true"))) 'COMPLETED 1 1
            #:accepted-results '("even:true"))
   (fixture 'artifact-first-pass 'first-pass
            '("artifact-good") '(("artifact-good" . "(artifact-good)"))
            '(("(artifact-good)" (ok "artifact:verified"))) 'COMPLETED 1 1
            #:accepted-results '("artifact:verified"))

   (fixture 'syntax-repair 'repair
            '("syntax-bad" "syntax-fixed")
            '(("syntax-bad" . "(syntax-bad)")
              ("syntax-fixed" . "(syntax-fixed)"))
            '(("(syntax-bad)" (error syntax "bad form"))
              ("(syntax-fixed)" (ok "42")))
            'COMPLETED 2 2 #:accepted-results '("42") #:repair-target? #t)
   (fixture 'runtime-repair 'repair
            '("runtime-bad" "runtime-fixed")
            '(("runtime-bad" . "(runtime-bad)")
              ("runtime-fixed" . "(runtime-fixed)"))
            '(("(runtime-bad)" (error runtime "unbound variable"))
              ("(runtime-fixed)" (ok "42")))
            'COMPLETED 2 2 #:accepted-results '("42") #:repair-target? #t)
   (fixture 'verifier-repair 'repair
            '("wrong-value" "right-value")
            '(("wrong-value" . "(wrong-value)")
              ("right-value" . "(right-value)"))
            '(("(wrong-value)" (ok "41"))
              ("(right-value)" (ok "42")))
            'COMPLETED 2 2 #:accepted-results '("42") #:repair-target? #t)
   (fixture 'two-stage-repair 'repair
            '("syntax-bad" "runtime-bad" "finally-good")
            '(("syntax-bad" . "(syntax-bad)")
              ("runtime-bad" . "(runtime-bad)")
              ("finally-good" . "(finally-good)"))
            '(("(syntax-bad)" (error syntax "bad form"))
              ("(runtime-bad)" (error runtime "bad value"))
              ("(finally-good)" (ok "42")))
            'COMPLETED 3 3 #:accepted-results '("42") #:repair-target? #t)

   (fixture 'missing-action 'planning
            '("no-code") '(("no-code" . #f)) '()
            'INSUFFICIENT_INFORMATION 1 0)
   (fixture 'missing-action-after-failure 'planning
            '("bad-action" "no-code")
            '(("bad-action" . "(bad-action)") ("no-code" . #f))
            '(("(bad-action)" (error syntax "bad form")))
            'INSUFFICIENT_INFORMATION 2 1)
   (fixture 'unknown-verifier 'verification
            '("observed") '(("observed" . "(observed)"))
            '(("(observed)" (ok "plausible")))
            'INCONCLUSIVE 1 1)
   (fixture 'unknown-verifier-after-repair 'verification
            '("bad" "observed")
            '(("bad" . "(bad)") ("observed" . "(observed)"))
            '(("(bad)" (error runtime "first failure"))
              ("(observed)" (ok "plausible")))
            'INCONCLUSIVE 2 2)
   (fixture 'verifier-rejection-exhausts-replans 'verification
            '("wrong-one" "wrong-two")
            '(("wrong-one" . "(wrong-one)") ("wrong-two" . "(wrong-two)"))
            '(("(wrong-one)" (ok "41")) ("(wrong-two)" (ok "40")))
            'FAILED 2 2 #:accepted-results '("42") #:max-replans 1)
   (fixture 'repeated-action-loop 'control
            '("same-one" "same-two")
            '(("same-one" . "(same)") ("same-two" . "(same)"))
            '(("(same)" (error runtime "repeatable failure")))
            'FAILED 2 1 #:max-replans 1)

   (fixture 'single-failure-budget 'control
            '("bad") '(("bad" . "(bad)"))
            '(("(bad)" (error syntax "bad")))
            'FAILURE_BUDGET_EXHAUSTED 1 1 #:max-failures 1)
   (fixture 'three-failure-budget 'control
            '("bad-one" "bad-two" "bad-three")
            '(("bad-one" . "(bad-one)")
              ("bad-two" . "(bad-two)")
              ("bad-three" . "(bad-three)"))
            '(("(bad-one)" (error syntax "bad one"))
              ("(bad-two)" (error syntax "bad two"))
              ("(bad-three)" (error syntax "bad three")))
            'FAILURE_BUDGET_EXHAUSTED 3 3 #:max-failures 3)
   (fixture 'transition-budget 'control
            '() '() '() 'BUDGET_EXHAUSTED 0 0 #:max-transitions 1)
   (fixture 'no-progress-budget 'control
            '() '() '() 'NO_PROGRESS 0 0 #:max-stalled-transitions 1)
   (fixture 'generation-adapter-failure 'adapter
            '((error "model unavailable")) '() '() 'FAILED 1 0)
   (fixture 'zero-replan-budget 'control
            '("bad") '(("bad" . "(bad)"))
            '(("(bad)" (error runtime "bad")))
            'FAILED 1 1 #:max-replans 0)

   (fixture 'interrupt-pending-generation 'interrupt
            '("late") '(("late" . "(late)"))
            '(("(late)" (ok "unexpected")))
            'USER_INTERRUPTED 1 0 #:mode 'delayed-interrupt)
   (fixture 'late-success-after-interrupt 'interrupt
            '("late") '(("late" . "(late)"))
            '(("(late)" (ok "unexpected")))
            'USER_INTERRUPTED 1 0 #:mode 'delayed-interrupt
            #:invoke-late-callback? #t)))

(define (lookup-equal key alist)
  (let ((entry (find (lambda (pair) (equal? (car pair) key)) alist)))
    (and entry (cdr entry))))

(define (lookup-execution key executions)
  (let ((entry (find (lambda (spec) (equal? (car spec) key)) executions)))
    (and entry (cadr entry))))

(define (make-fixture-verifier accepted-results)
  (if (not accepted-results)
      default-goal-verifier
      (lambda (goal action result evidence execution-claim state)
        (if (member (co-content result) accepted-results)
            (make-goal-verdict
             'SATISFIED
             "The deterministic corpus oracle accepted the observed result."
             (string-append "Verified fixture result: " (co-content result)))
            (make-goal-verdict
             'REJECTED
             "The deterministic corpus oracle rejected the observed result.")))))

(define (run-fixture case)
  (let* ((session (make-cognitive-session #:workspace-capacity 8))
         (responses (assoc-ref case 'responses))
         (actions (assoc-ref case 'actions))
         (executions (assoc-ref case 'executions))
         (generation-count 0)
         (execution-count 0)
         (finish-records '())
         (late-success #f)
         (unexpected-adapter-call? #f)
         (started (get-internal-real-time))
         (process
          (start-production-process!
           session (symbol->string (assoc-ref case 'id))
           #:completion-criteria (assoc-ref case 'completion-criteria)
           #:max-transitions (assoc-ref case 'max-transitions)
           #:max-stalled-transitions (assoc-ref case 'max-stalled-transitions)
           #:max-failures (assoc-ref case 'max-failures)
           #:max-replans (assoc-ref case 'max-replans)
           #:verify-goal (make-fixture-verifier (assoc-ref case 'accepted-results))
           #:generate
           (lambda (prompt succeed fail)
             (let ((index generation-count))
               (set! generation-count (+ generation-count 1))
               (if (>= index (length responses))
                   (begin
                     (set! unexpected-adapter-call? #t)
                     (fail "fixture response sequence exhausted"))
                   (let ((spec (list-ref responses index)))
                     (cond
                      ((eq? (assoc-ref case 'mode) 'delayed-interrupt)
                       (set! late-success succeed))
                      ((and (pair? spec) (eq? (car spec) 'error))
                       (fail (cadr spec)))
                      (else (succeed spec)))))))
           #:extract-action (lambda (response) (lookup-equal response actions))
           #:execute
           (lambda (code succeed fail)
             (set! execution-count (+ execution-count 1))
             (let ((spec (lookup-execution code executions)))
               (if (not spec)
                   (begin
                     (set! unexpected-adapter-call? #t)
                     (fail 'fixture "missing execution fixture"))
                   (match spec
                     (('ok value) (succeed value))
                     (('error type message) (fail type message))
                     (_
                      (set! unexpected-adapter-call? #t)
                      (fail 'fixture "invalid execution fixture"))))))
           #:on-finished
           (lambda (outcome final-text hypothesis-text)
             (set! finish-records
                   (cons (list outcome final-text hypothesis-text) finish-records))))))
    (when (eq? (assoc-ref case 'mode) 'delayed-interrupt)
      (session-request-interrupt! session)
      (when (assoc-ref case 'invoke-late-callback?)
        (late-success (car responses))))
    (let* ((events (state-events (session-state session)))
           (terminals
            (filter (lambda (event)
                      (memq (event-type event) '(GoalCompleted ProcessTerminated)))
                    events))
           (actual-outcome (process-outcome process))
           (hang? (or (process-active? process) (null? finish-records)))
           (false-completion?
            (and (eq? actual-outcome 'COMPLETED)
                 (not (eq? (assoc-ref case 'expected-outcome) 'COMPLETED))))
           (passed?
            (and (not unexpected-adapter-call?)
                 (not hang?)
                 (not false-completion?)
                 (eq? actual-outcome (assoc-ref case 'expected-outcome))
                 (= generation-count (assoc-ref case 'expected-generations))
                 (= execution-count (assoc-ref case 'expected-executions))
                 (= (length terminals) 1)
                 (= (length finish-records) 1)
                 (eq? (caar finish-records) actual-outcome)))
           (elapsed-ms
            (* 1000.0
               (/ (- (get-internal-real-time) started)
                  internal-time-units-per-second))))
      `((id . ,(assoc-ref case 'id))
        (category . ,(assoc-ref case 'category))
        (passed? . ,passed?)
        (hang? . ,hang?)
        (false-completion? . ,false-completion?)
        (repair-target? . ,(assoc-ref case 'repair-target?))
        (actual-outcome . ,actual-outcome)
        (expected-outcome . ,(assoc-ref case 'expected-outcome))
        (generations . ,generation-count)
        (executions . ,execution-count)
        (terminal-events . ,(length terminals))
        (finish-callbacks . ,(length finish-records))
        (elapsed-ms . ,elapsed-ms)))))

(define results (map run-fixture corpus))
(define failures (filter (lambda (result) (not (assoc-ref result 'passed?))) results))
(define hangs (count (lambda (result) (assoc-ref result 'hang?)) results))
(define false-completions
  (count (lambda (result) (assoc-ref result 'false-completion?)) results))
(define repair-results
  (filter (lambda (result) (assoc-ref result 'repair-target?)) results))
(define repaired
  (count (lambda (result) (and (assoc-ref result 'passed?)
                               (eq? (assoc-ref result 'actual-outcome) 'COMPLETED)))
         repair-results))
(define total-generations
  (fold + 0 (map (lambda (result) (assoc-ref result 'generations)) results)))
(define total-executions
  (fold + 0 (map (lambda (result) (assoc-ref result 'executions)) results)))
(define total-elapsed-ms
  (fold + 0.0 (map (lambda (result) (assoc-ref result 'elapsed-ms)) results)))
(define max-elapsed-ms
  (fold max 0.0 (map (lambda (result) (assoc-ref result 'elapsed-ms)) results)))
(define interrupt-results
  (filter (lambda (result) (eq? (assoc-ref result 'category) 'interrupt)) results))
(define max-interrupt-ms
  (fold max 0.0
        (map (lambda (result) (assoc-ref result 'elapsed-ms)) interrupt-results)))

(for-each
 (lambda (result)
   (format #t "~a ~a [~a] outcome=~a model=~a exec=~a terminal=~a callback=~a latency=~,2fms\n"
           (if (assoc-ref result 'passed?) "PASS" "FAIL")
           (assoc-ref result 'id)
           (assoc-ref result 'category)
           (assoc-ref result 'actual-outcome)
           (assoc-ref result 'generations)
           (assoc-ref result 'executions)
           (assoc-ref result 'terminal-events)
           (assoc-ref result 'finish-callbacks)
           (assoc-ref result 'elapsed-ms)))
 results)

(format #t
        "\nGCAS deterministic evaluation: cases=~a passed=~a failed=~a hangs=~a false-completions=~a repair-success=~a/~a model-calls=~a executions=~a latency-avg=~,2fms latency-max=~,2fms interrupt-max=~,2fms\n"
        (length results)
        (- (length results) (length failures))
        (length failures)
        hangs
        false-completions
        repaired
        (length repair-results)
        total-generations
        total-executions
        (/ total-elapsed-ms (length results))
        max-elapsed-ms
        max-interrupt-ms)

(unless (null? failures)
  (for-each (lambda (failure) (format #t "FAILED FIXTURE: ~s\n" failure)) failures))

(exit (if (null? failures) 0 1))
