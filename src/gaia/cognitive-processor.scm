(define-module (gaia cognitive-processor)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-session)
  #:export (<cognitive-processor>
            <processor-proposal>
            make-cognitive-processor
            cognitive-processor?
            processor-id
            processor-subscriptions
            processor-handler
            make-processor-proposal
            processor-proposal?
            proposal-object
            proposal-priority
            proposal-relevance
            proposal-risk
            proposal-cost
            proposal-uncertainty
            submit-processor-proposal!
            attach-processor!))

;; Processors are intentionally small and stateless at this layer.  Their
;; durable state belongs in Cognitive State or Memory, while this contract says
;; exactly how an event can produce a candidate for the shared workspace.
(define-record-type <cognitive-processor>
  (%make-processor id subscriptions handler)
  cognitive-processor?
  (id processor-id)
  (subscriptions processor-subscriptions)
  (handler processor-handler))

(define-record-type <processor-proposal>
  (%make-proposal object priority relevance risk cost uncertainty)
  processor-proposal?
  (object proposal-object)
  (priority proposal-priority)
  (relevance proposal-relevance)
  (risk proposal-risk)
  (cost proposal-cost)
  (uncertainty proposal-uncertainty))

(define (event-filter? filter)
  (or (symbol? filter) (procedure? filter)))

(define (make-cognitive-processor id subscriptions handler)
  "Create a processor.  HANDLER receives an event and returns zero or more
processor proposals.  A subscription is an event type symbol or predicate."
  (unless (and (symbol? id) (not (null? subscriptions)) (procedure? handler)
               (every event-filter? subscriptions))
    (error "Invalid cognitive processor contract" id subscriptions handler))
  (%make-processor id subscriptions handler))

(define* (make-processor-proposal object
                                  #:key
                                  (priority 0)
                                  (relevance 0)
                                  (risk 0)
                                  (cost 0)
                                  (uncertainty 0))
  (unless (cognitive-object? object)
    (error "Processor proposals must contain a Cognitive Object" object))
  (%make-proposal object priority relevance risk cost uncertainty))

(define (submit-processor-proposal! session processor proposal)
  (unless (processor-proposal? proposal)
    (error "Processor handler must return processor proposals" proposal))
  (session-submit! session (proposal-object proposal)
                   #:priority (proposal-priority proposal)
                   #:relevance (proposal-relevance proposal)
                   #:risk (proposal-risk proposal)
                   #:cost (proposal-cost proposal)
                   #:uncertainty (proposal-uncertainty proposal)
                   #:origin (processor-id processor)))

(define* (attach-processor! session processor #:key (after-submit #f))
  "Subscribe PROCESSOR to SESSION's bus.  Handler exceptions are isolated by
the bus; valid returned proposals become candidates, never direct broadcasts."
  (unless (and (cognitive-session? session) (cognitive-processor? processor))
    (error "attach-processor! requires a session and processor" session processor))
  (unless (or (not after-submit) (procedure? after-submit))
    (error "after-submit must be a procedure or #f" after-submit))
  (map (lambda (subscription)
         (bus-subscribe
          (session-bus session) subscription
          (lambda (event)
            (for-each (lambda (proposal) (submit-processor-proposal! session processor proposal))
                      ((processor-handler processor) event))
            (when after-submit (after-submit)))))
       (processor-subscriptions processor)))
