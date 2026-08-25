(use-modules (gaia ncsi-evaluation))

(define (assert-equal label expected actual)
  (unless (equal? expected actual)
    (error "Assertion failed" label expected actual)))

(define (result mode repetition observations concepts proposals)
  `(("task" . "task")
    ("mode" . ,mode)
    ("repetition" . ,repetition)
    ("terminal" . #t)
    ("fallback" . #f)
    ("success" . #t)
    ("final-text" . "Paris")
    ("token-count" . 1)
    ("observation-count" . ,observations)
    ("workspace-proposals" . ,proposals)
    ("concepts" . ,concepts)
    ("latency-seconds" . 0.1)))

(let* ((results
        (list (result "TEXT_ONLY" 1 0 #() 0)
              (result "TEXT_ONLY" 2 0 #() 0)
              (result "OBSERVATION_ONLY" 1 1 #("Paris" "France") 0)
              (result "OBSERVATION_ONLY" 2 1 #("Paris" "capital") 0)
              (result "NCSI_POLICY" 1 1 #("Paris" "France") 1)
              (result "NCSI_POLICY" 2 1 #("Paris" "capital") 1)))
       (summary (summarize-ncsi-evaluation results)))
  (assert-equal "matched output invariant" #t
                (assoc-ref summary "matched-text-observation-output"))
  (assert-equal "readiness decision" "SHIP_EXPERIMENTAL"
                (assoc-ref summary "decision")))

(display "NCSI M5 evaluation summary tests passed\n")
