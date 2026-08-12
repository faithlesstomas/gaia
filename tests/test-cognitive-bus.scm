(define-module (tests test-cognitive-bus)
  #:use-module (srfi srfi-64)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus))

(test-begin "gaia-cognitive-bus")

(test-group "cognitive-events"
  (test-assert "make-cognitive-event creates valid event"
    (let* ((co (make-cognitive-object 'goal "Find key" #:provenance 'USER))
           (evt (make-goal-created-event co)))
      (and (cognitive-event? evt)
           (eq? (event-type evt) 'GoalCreated)
           (eq? (event-payload evt) co)
           (eq? (event-origin evt) 'USER)))))

(test-group "bus-publish-subscribe"
  (test-assert "bus publishes event to subscribed handler"
    (let ((bus (make-cognitive-bus))
          (received '()))
      (bus-subscribe bus 'GoalCreated (lambda (evt) (set! received (cons evt received))))
      (let* ((co (make-cognitive-object 'goal "Search directory"))
             (evt (make-goal-created-event co)))
        (bus-publish bus evt)
        (and (= (length received) 1)
             (eq? (car received) evt)))))

  (test-assert "bus filters events by subscriber predicate"
    (let ((bus (make-cognitive-bus))
          (hypothesis-count 0))
      (bus-subscribe bus 'HypothesisProposed (lambda (evt) (set! hypothesis-count (+ hypothesis-count 1))))
      (let ((co1 (make-cognitive-object 'goal "Goal"))
            (co2 (make-cognitive-object 'hypothesis "Hypothesis")))
        (bus-publish bus (make-goal-created-event co1))
        (bus-publish bus (make-hypothesis-proposed-event co2))
        (= hypothesis-count 1))))

  (test-assert "bus-retract and bus-supersede emit semantic control events"
    (let ((bus (make-cognitive-bus))
          (retracted-id #f)
          (superseded-pair #f))
      (bus-subscribe bus 'CO_Retracted (lambda (evt) (set! retracted-id (event-payload evt))))
      (bus-subscribe bus 'CO_Superseded (lambda (evt) (set! superseded-pair (event-payload evt))))
      (bus-retract bus "co-100")
      (bus-supersede bus "co-100" "co-101")
      (and (string=? retracted-id "co-100")
           (equal? superseded-pair `(("old-id" . "co-100") ("new-co" . "co-101")))))))

(test-end "gaia-cognitive-bus")
