(define-module (tests test-goal-verifier)
  #:use-module (srfi srfi-64)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-state)
  #:use-module (gaia goal-verifier))

(test-begin "gaia-goal-verifier")

(define (make-fixture)
  (let* ((goal (make-cognitive-object 'goal "Verify a bounded result" #:provenance 'USER))
         (action (make-cognitive-object 'action "(bounded-check)" #:provenance 'LLM))
         (result (make-cognitive-object 'result "42" #:provenance 'REPL))
         (evidence (make-cognitive-object 'evidence "Observed 42" #:provenance 'EXECUTION))
         (claim (make-cognitive-object 'claim "The action observed 42."
                                       #:provenance 'SYMBOLIC_INFERENCE)))
    (list goal action result evidence claim)))

(test-assert "the default verifier refuses to complete an arbitrary natural-language Goal"
  (let* ((fixture (make-fixture))
         (verdict (apply (lambda (goal action result evidence claim)
                           (call-goal-verifier default-goal-verifier goal action result evidence claim
                                               (make-cognitive-state)))
                         fixture)))
    (and (goal-verdict? verdict)
         (eq? (goal-verdict-status verdict) 'INCONCLUSIVE))))

(test-assert "a verifier must return an explicit Goal verdict"
  (catch #t
    (lambda ()
      (let ((fixture (make-fixture)))
        (apply (lambda (goal action result evidence claim)
                 (call-goal-verifier (lambda args #t) goal action result evidence claim
                                     (make-cognitive-state)))
               fixture))
      #f)
    (lambda _ #t)))

(test-assert "the production selector requires a hidden-test Fibonacci summary"
  (let* ((fixture (make-fixture))
         (result (list-ref fixture 2))
         (accepted-result
          (make-cognitive-object 'result "((passed . 4) (failed . 0))"
                                 #:provenance 'REPL))
         (accepted-action
          (make-cognitive-object
           'action
           "(define (fibonacci-sequence n)\n  (let loop ((remaining n) (a 0) (b 1) (out '()))\n    (if (= remaining 0) (reverse out)\n        (loop (- remaining 1) b (+ a b) (cons a out)))))"
           #:provenance 'LLM))
         (verifier (select-goal-verifier
                    "Napisz funkcję liczącą wyrazy ciągu Fibonacciego"))
         (verdict (verifier (list-ref fixture 0)
                            accepted-action
                            accepted-result
                            (list-ref fixture 3)
                            (list-ref fixture 4)
                            (make-cognitive-state))))
    (and (eq? (goal-verdict-status verdict) 'SATISFIED)
         (string-contains (goal-verdict-claim-content verdict)
                          "hidden behavioral tests")
         (string-contains
          (goal-completion-criteria "Fibonacci sequence")
          "private deterministic test suite"))))

(test-end "gaia-goal-verifier")
