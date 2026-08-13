(define-module (gaia deliberative-processor)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia cognitive-state)
  #:export (deliberate-execution!))

;; The first production deliberative processor.  A verifier is deliberately an
;; injected procedure: an LLM may propose an expectation, but cannot implement
;; this decision simply by declaring itself correct.
(define* (deliberate-execution! session action-co result-co verifier
                                #:key (claim-content #f))
  "Turn an execution observation into Evidence and either an accepted Claim or
an explicit Conflict.  VERIFIER receives ACTION and RESULT and returns #t only
when the observation meets the independently supplied criterion."
  (unless (and (cognitive-session? session) (cognitive-object? action-co)
               (cognitive-object? result-co) (procedure? verifier))
    (error "Invalid deliberation inputs" session action-co result-co verifier))
  (let ((evidence (make-cognitive-object
                   'evidence (string-append "Execution observed: " (co-content result-co))
                   #:provenance 'EXECUTION
                   #:relations `((observes . ,(co-id result-co))
                                 (produced-by . ,(co-id action-co))))))
    (session-submit! session evidence #:priority 95 #:relevance 1 #:origin 'DELIBERATIVE)
    (session-advance! session)
    (session-emit! session 'EvidenceFound evidence #:origin 'DELIBERATIVE)
    (if (verifier action-co result-co)
        (let ((claim (make-cognitive-object
                      'claim (or claim-content (co-content action-co))
                      #:provenance 'SYMBOLIC_INFERENCE
                      #:epistemic-status 'ACCEPTED
                      #:verification-status 'VERIFIED
                      #:relations `((supported-by . ,(co-id evidence))
                                    (derived-from . ,(co-id action-co))))))
          (session-submit! session claim #:priority 100 #:relevance 1 #:origin 'DELIBERATIVE)
          (session-advance! session)
          (session-emit! session 'BeliefUpdated claim #:origin 'DELIBERATIVE)
          claim)
        (let ((conflict (make-cognitive-object
                         'conflict "Execution evidence does not satisfy the verification criterion."
                         #:provenance 'EXECUTION
                         #:relations `((contradicts . ,(co-id action-co))
                                       (evidence . ,(co-id evidence))))))
          (session-submit! session conflict #:priority 100 #:relevance 1 #:origin 'DELIBERATIVE)
          (session-advance! session)
          (session-emit! session 'ConflictDetected conflict #:origin 'DELIBERATIVE)
          conflict))))
