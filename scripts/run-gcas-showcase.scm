(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (gaia gcas-showcase)
             (gaia com)
             (gaia cognitive-bus))

(define (event-types result)
  (map event-type (assoc-ref result 'events)))

(let ((result (run-gcas-reference-cycle)))
  (format #t "GCAS-Core reference-cycle showcase~%")
  (format #t "Outcome: ~a~%" (assoc-ref result 'outcome))
  (let ((claim (assoc-ref result 'claim)))
    (when claim
      (format #t "Accepted claim: ~a~%" (co-content claim))))
  (format #t "Events: ~s~%" (event-types result)))
