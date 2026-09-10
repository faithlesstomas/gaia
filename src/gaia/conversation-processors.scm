(define-module (gaia conversation-processors)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-control)
  #:use-module (gaia cognitive-memory)
  #:use-module (gaia cognitive-process)
  #:use-module (gaia cognitive-processor)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia cognitive-state)
  #:export (start-conversation-process!))

(define (relation-ref co key)
  (and (cognitive-object? co) (assoc-ref (co-relations co) key)))

(define (belongs-to-process? co process)
  (and (cognitive-object? co)
       (or (equal? (relation-ref co 'process) (process-id process))
           (equal? (co-id co) (co-id (process-goal process))))))

(define (active-process? session process)
  (let ((current (session-current-process session)))
    (and current (eq? current process) (process-active? process))))

(define* (start-conversation-process!
          session utterance
          #:key
          generate
          (on-client-event (lambda _ #t))
          (on-finished (lambda _ #t))
          (recent-limit 6)
          (relevant-limit 5)
          (max-context-chars 6000)
          (max-response-chars 16000)
          (max-transitions 16)
          (max-stalled-transitions 6))
  "Run one ordinary assistant turn as a bounded GCAS Cognitive Process.

GENERATE receives a reconstructed prompt and success/failure callbacks. It is
the only model boundary; callers must pass an empty protocol chat history. A
successful delivery completes the conversational Goal through an independently
constructed structural Claim, while the assistant response itself remains an
LLM HYPOTHESIS/UNVERIFIED."
  (unless (and (cognitive-session? session)
               (string? utterance)
               (> (string-length (string-trim-both utterance)) 0)
               (procedure? generate)
               (procedure? on-client-event)
               (procedure? on-finished)
               (integer? recent-limit) (>= recent-limit 0)
               (integer? relevant-limit) (>= relevant-limit 0)
               (integer? max-context-chars) (>= max-context-chars 512)
               (integer? max-response-chars) (> max-response-chars 0))
    (error "Invalid GCAS conversation process configuration" session utterance))
  (let* ((completion-criteria
          "Deliver one non-empty bounded conversational response whose content remains explicitly unverified.")
         (goal
          (make-cognitive-object
           'goal utterance #:provenance 'USER
           #:relations `((completion-criteria . ,completion-criteria)
                         (process-kind . CONVERSATION))))
         (process
          (session-start-process!
           session goal completion-criteria
           #:max-transitions max-transitions
           #:max-stalled-transitions max-stalled-transitions
           #:max-failures 1))
         (process-id* (process-id process))
         (prior-turns
          (memory-conversation-turns (session-memory session) #:limit 1))
         (prior-turn (and (pair? prior-turns) (car prior-turns)))
         (user-turn
          (memory-record-conversation-turn!
           (session-memory session) 'USER utterance
           #:in-reply-to (and prior-turn (co-id prior-turn))
           #:process-id process-id*))
         (subscriptions-cell (list '()))
         (round-running-cell (list #f))
         (round-requested-cell (list #f))
         (client-finished-cell (list #f))
         (response-cell (list #f))
         (delivery-claim-cell (list #f)))

    (define (detach!)
      (for-each (lambda (subscription)
                  (bus-unsubscribe (session-bus session) subscription))
                (car subscriptions-cell))
      (set-car! subscriptions-cell '()))

    (define (request-round!)
      (when (active-process? session process)
        (set-car! round-requested-cell #t)
        (unless (car round-running-cell)
          (set-car! round-running-cell #t)
          (let loop ()
            (when (and (active-process? session process)
                       (car round-requested-cell))
              (set-car! round-requested-cell #f)
              (session-run-workspace-round! session)
              (when (car round-requested-cell) (loop))))
          (set-car! round-running-cell #f))))

    (define (control-terminal-text outcome)
      (case outcome
        ((USER_INTERRUPTED)
         "USER_INTERRUPTED: the conversation was interrupted by the user.")
        ((BUDGET_EXHAUSTED NO_PROGRESS)
         "INCONCLUSIVE: the conversation process exhausted its progress budget.")
        (else
         (format #f "FAILED: the conversation process terminated with ~a."
                 outcome))))

    (define (consolidate-response! claim)
      (let ((response (car response-cell)))
        (when response
          (let ((delivered
                 (if claim
                     (co-add-relation response 'delivery-verified-by
                                      (co-id claim))
                     response)))
            (state-store! (session-state session) delivered)
            (memory-consolidate!
             (session-memory session) (list delivered)
             #:reason 'CONVERSATION_TURN
             #:revalidation 'ON_RELATED_CONVERSATION)))))

    (define (notify-finished! outcome final-text)
      (unless (car client-finished-cell)
        (set-car! client-finished-cell #t)
        (when (eq? outcome 'COMPLETED)
          (consolidate-response! (car delivery-claim-cell)))
        (on-finished outcome final-text
                     (if (car response-cell)
                         (co-content (car response-cell))
                         ""))))

    (define (emit-answer! outcome final-text . optional-claim)
      (when (active-process? session process)
        (let ((claim (and (pair? optional-claim) (car optional-claim))))
          (session-emit!
           session 'AnswerRequested
           `((process-id . ,process-id*)
             (outcome . ,outcome)
             (final-text . ,final-text)
             (verified-claim . ,(and claim (co-id claim))))
           #:origin 'CONTROL))))

    (letrec
        ((memory-processor
          (make-cognitive-processor
           'MEMORY '(GoalCreated)
           (lambda (event)
             (let ((event-goal (event-payload event)))
               (if (and (active-process? session process)
                        (cognitive-object? event-goal)
                        (equal? (co-id event-goal) (co-id goal)))
                   (let* ((retrieval
                           (memory-retrieve-conversation
                            (session-memory session) utterance
                            #:recent-limit recent-limit
                            #:relevant-limit relevant-limit
                            #:exclude-ids (list (co-id user-turn))))
                          (context
                           (reconstruct-conversation-context
                            goal retrieval #:max-chars max-context-chars))
                          (context-co
                           (make-cognitive-object
                            'observation context #:provenance 'MEMORY
                            #:relations `((process . ,process-id*)
                                          (context-for . ,(co-id goal))
                                          (projection-kind . CONVERSATION)
                                          (history-replayed . #f)
                                          (max-context-chars . ,max-context-chars)))))
                     (session-emit! session 'MemoryRetrieved context-co
                                    #:origin 'MEMORY)
                     (list (make-processor-proposal
                            context-co #:priority 80 #:relevance 1)))
                   '())))))

         (generative-processor
          (make-cognitive-processor
           'GENERATIVE '(WorkspaceBroadcast)
           (lambda (event)
             (let ((context (event-payload event)))
               (when (and (active-process? session process)
                          (belongs-to-process? context process)
                          (eq? (co-type context) 'observation)
                          (eq? (relation-ref context 'projection-kind)
                               'CONVERSATION))
                 (generate
                  (co-content context)
                  (lambda (response-text)
                    (when (active-process? session process)
                      (if (and (string? response-text)
                               (> (string-length
                                   (string-trim-both response-text)) 0)
                               (<= (string-length response-text)
                                   max-response-chars))
                          (let ((response
                                 (make-conversation-turn
                                  (session-memory session) 'ASSISTANT
                                  response-text
                                  #:in-reply-to (co-id user-turn)
                                  #:process-id process-id*)))
                            (set-car! response-cell response)
                            (control-record-progress! (session-control session))
                            (submit-processor-proposal!
                             session generative-processor
                             (make-processor-proposal
                              response #:priority 90 #:relevance 1
                              #:uncertainty 1))
                            (request-round!))
                          (emit-answer!
                           'INSUFFICIENT_INFORMATION
                           "INCONCLUSIVE: the model returned an empty or oversized conversational response."))))
                  (lambda (error-text)
                    (emit-answer!
                     'FAILED
                     (string-append
                      "FAILED: GCAS conversational generation failed: "
                      (format #f "~a" error-text)))))))
             '())))

         (delivery-verifier-processor
          (make-cognitive-processor
           'GOAL_VERIFIER '(WorkspaceBroadcast)
           (lambda (event)
             (let ((payload (event-payload event)))
               (cond
                ((and (active-process? session process)
                      (belongs-to-process? payload process)
                      (eq? (co-type payload) 'hypothesis)
                      (eq? (relation-ref payload 'conversation-speaker)
                           'ASSISTANT))
                 (session-emit! session 'HypothesisProposed payload
                                #:origin 'GENERATIVE)
                 (let ((evidence
                        (make-cognitive-object
                         'evidence
                         "A non-empty bounded assistant response was produced for the active conversation turn; its factual content was not verified."
                         #:provenance 'SYMBOLIC_INFERENCE
                         #:relations `((process . ,process-id*)
                                       (observes . ,(co-id payload))
                                       (for-goal . ,(co-id goal))
                                       (verification-scope . DELIVERY_ONLY)))))
                   (session-emit! session 'ResponseDeliveryVerified evidence
                                  #:origin 'GOAL_VERIFIER)
                   (list (make-processor-proposal
                          evidence #:priority 95 #:relevance 1))))
                ((and (active-process? session process)
                      (belongs-to-process? payload process)
                      (eq? (co-type payload) 'evidence)
                      (eq? (relation-ref payload 'verification-scope)
                           'DELIVERY_ONLY))
                 (let ((claim
                        (make-cognitive-object
                         'claim
                         "The active conversational Goal received one structurally valid response; no factual proposition in that response is thereby verified."
                         #:provenance 'SYMBOLIC_INFERENCE
                         #:epistemic-status 'ACCEPTED
                         #:verification-status 'VERIFIED
                         #:relations `((process . ,process-id*)
                                       (satisfies . ,(co-id goal))
                                       (supported-by . ,(co-id payload))
                                       (delivers . ,(relation-ref payload 'observes))
                                       (verification-scope . DELIVERY_ONLY)))))
                   (set-car! delivery-claim-cell claim)
                   (session-emit!
                    session 'GoalVerificationCompleted
                    `((process-id . ,process-id*)
                      (goal . ,(co-id goal))
                      (claim . ,(co-id claim))
                      (status . SATISFIED)
                      (scope . DELIVERY_ONLY))
                    #:origin 'GOAL_VERIFIER)
                   (list (make-processor-proposal
                          claim #:priority 100 #:relevance 1))))
                (else '()))))))

         (answer-processor
          (make-cognitive-processor
           'ANSWER '(WorkspaceBroadcast AnswerRequested)
           (lambda (event)
             (cond
              ((and (eq? (event-type event) 'WorkspaceBroadcast)
                    (active-process? session process)
                    (let ((claim (event-payload event)))
                      (and (belongs-to-process? claim process)
                           (fact? claim)
                           (eq? (relation-ref claim 'verification-scope)
                                'DELIVERY_ONLY)
                           (equal? (relation-ref claim 'satisfies)
                                   (co-id goal)))))
               (let ((claim (event-payload event))
                     (response (car response-cell)))
                 (session-emit! session 'GoalVerified claim
                                #:origin 'GOAL_VERIFIER)
                 (emit-answer! 'COMPLETED (co-content response) claim))
               '())
              ((eq? (event-type event) 'AnswerRequested)
               (let ((request (event-payload event)))
                 (when (and (active-process? session process)
                            (equal? (assoc-ref request 'process-id)
                                    process-id*))
                   (let* ((outcome (assoc-ref request 'outcome))
                          (final-text (assoc-ref request 'final-text))
                          (claim-id (assoc-ref request 'verified-claim))
                          (claim (and claim-id
                                      (state-find (session-state session)
                                                  claim-id))))
                     (detach!)
                     (if (eq? outcome 'COMPLETED)
                         (when (session-complete-goal! session claim)
                           (notify-finished! outcome final-text))
                         (when (session-finish-process! session outcome)
                           (notify-finished! outcome final-text))))))
               '())
              (else '())))))

         (lifecycle-processor
          (make-cognitive-processor
           'CONTROL '(GoalCompleted ProcessTerminated ProcessorFailed)
           (lambda (event)
             (cond
              ((and (eq? (event-type event) 'ProcessorFailed)
                    (active-process? session process))
               (emit-answer!
                'FAILED
                (format #f "FAILED: conversational processor error: ~s"
                        (event-payload event))))
              ((and (memq (event-type event)
                          '(GoalCompleted ProcessTerminated))
                    (eq? (session-current-process session) process))
               (let ((outcome (process-outcome process)))
                 (detach!)
                 (notify-finished! outcome
                                   (control-terminal-text outcome))))
              (else #f))
             '()))))

      (let ((processors (list memory-processor generative-processor
                              delivery-verifier-processor answer-processor
                              lifecycle-processor)))
        (set-car! subscriptions-cell
                  (append-map
                   (lambda (processor)
                     (attach-processor! session processor
                                        #:after-submit request-round!))
                   processors)))

      (session-submit! session user-turn #:priority 20 #:relevance 1
                       #:origin 'USER)
      (session-emit! session 'ConversationTurnReceived user-turn #:origin 'USER)
      (session-submit! session goal #:priority 100 #:relevance 1 #:origin 'USER)
      (session-emit! session 'GoalCreated goal #:origin 'CONTROL)
      (memory-store! (session-memory session) goal)
      (request-round!)
      process)))
