(define-module (gaia production-processors)
  #:use-module (srfi srfi-1)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-memory)
  #:use-module (gaia cognitive-process)
  #:use-module (gaia cognitive-processor)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia cognitive-state)
  #:use-module (gaia workspace)
  #:export (start-production-process!))

(define (relation-ref co key)
  (and (cognitive-object? co) (assoc-ref (co-relations co) key)))

(define (belongs-to-process? co process)
  (and (cognitive-object? co)
       (or (equal? (relation-ref co 'process) (process-id process))
           (equal? (co-id co) (co-id (process-goal process))))))

(define (active-process? session process)
  (let ((current (session-current-process session)))
    (and current
         (eq? current process)
         (process-active? process))))

(define (answer-request process outcome final-text hypothesis-text)
  `((process-id . ,(process-id process))
    (outcome . ,outcome)
    (final-text . ,final-text)
    (hypothesis-text . ,hypothesis-text)))

(define* (start-production-process!
          session task
          #:key
          generate
          execute
          extract-action
          (on-client-event (lambda _ #t))
          (on-finished (lambda _ #t))
          (completion-criteria "Produce independently verified evidence that satisfies the user Goal.")
          (max-transitions 32)
          (max-stalled-transitions 8)
          (max-failures 3))
  "Start one production cognitive process and attach its processors to the Bus.

GENERATE accepts PROMPT, SUCCESS and FAILURE callbacks. EXECUTE accepts ACTION
text, SUCCESS and FAILURE callbacks. This adapter boundary keeps the cognitive
process independent from Goblins actors and from a particular LLM/runtime."
  (unless (and (cognitive-session? session) (string? task)
               (procedure? generate) (procedure? execute)
               (procedure? extract-action) (procedure? on-client-event)
               (procedure? on-finished))
    (error "Invalid production process adapters" session task))
  (let* ((goal (make-cognitive-object
                'goal task #:provenance 'USER
                #:relations `((completion-criteria . ,completion-criteria))))
         (process (session-start-process!
                   session goal completion-criteria
                   #:max-transitions max-transitions
                   #:max-stalled-transitions max-stalled-transitions
                   #:max-failures max-failures))
         (process-id* (process-id process))
         (question (make-cognitive-object
                    'question task #:provenance 'USER
                    #:relations `((process . ,process-id*)
                                  (resolved-by . ,(co-id goal)))))
         (subscriptions-cell (list '()))
         (hypothesis-text-cell (list "")))

    (define (emit-answer! outcome final-text hypothesis-text)
      (when (active-process? session process)
        (session-emit! session 'AnswerRequested
                       (answer-request
                        process outcome final-text
                        (if (> (string-length hypothesis-text) 0)
                            hypothesis-text
                            (car hypothesis-text-cell)))
                       #:origin 'CONTROL)))

    (define (detach!)
      (for-each (lambda (subscription)
                  (bus-unsubscribe (session-bus session) subscription))
                (car subscriptions-cell))
      (set-car! subscriptions-cell '()))

    (letrec
        ((scheduler
          (make-cognitive-processor
           'CONTROL '(CandidateSubmitted)
           (lambda (event)
             (when (active-process? session process)
               (session-advance! session))
             '())))

         (memory-processor
          (make-cognitive-processor
           'MEMORY '(GoalCreated)
           (lambda (event)
             (let ((event-goal (event-payload event)))
               (if (and (active-process? session process)
                        (cognitive-object? event-goal)
                        (equal? (co-id event-goal) (co-id goal)))
                   (let* ((selected (memory-retrieve (session-memory session) task))
                          (context (reconstruct-context
                                    goal
                                    (workspace-active (session-workspace session))
                                    selected
                                    #:constraints
                                    (list completion-criteria
                                          "Use an explicit Action before requesting execution."
                                          "Treat model output as an unverified hypothesis.")))
                          (context-co
                           (make-cognitive-object
                            'observation context #:provenance 'MEMORY
                            #:relations `((process . ,process-id*)
                                          (context-for . ,(co-id goal))))))
                     (session-emit! session 'MemoryRetrieved context-co #:origin 'MEMORY)
                     (list (make-processor-proposal context-co
                                                    #:priority 80
                                                    #:relevance 1)))
                   '())))))

         (generative-processor
          (make-cognitive-processor
           'GENERATIVE '(WorkspaceBroadcast)
           (lambda (event)
             (let ((co (event-payload event)))
               (when (and (active-process? session process)
                          (belongs-to-process? co process)
                          (eq? (co-type co) 'observation)
                          (relation-ref co 'context-for))
                 (generate
                  (co-content co)
                  (lambda (response-text)
                    (when (active-process? session process)
                      (set-car! hypothesis-text-cell response-text)
                      (submit-processor-proposal!
                       session generative-processor
                       (make-processor-proposal
                        (make-cognitive-object
                         'hypothesis response-text #:provenance 'LLM
                         #:relations `((process . ,process-id*)
                                       (addresses . ,(co-id goal))))
                        #:priority 70 #:relevance 1 #:uncertainty 1))))
                  (lambda (error-text)
                    (emit-answer! 'FAILED
                                  (string-append "GCAS generative processor failed: " error-text)
                                  ""))))
             '()))))

         (planner-processor
          (make-cognitive-processor
           'PLANNER '(WorkspaceBroadcast)
           (lambda (event)
             (let ((co (event-payload event)))
               (if (and (active-process? session process)
                        (belongs-to-process? co process)
                        (eq? (co-type co) 'hypothesis))
                   (let ((action-text (extract-action (co-content co))))
                     (session-emit! session 'HypothesisProposed co #:origin 'GENERATIVE)
                     (if action-text
                         (list
                          (make-processor-proposal
                           (make-cognitive-object
                            'action action-text #:provenance 'LLM
                            #:relations `((process . ,process-id*)
                                          (tests . ,(co-id co))
                                          (serves . ,(co-id goal))))
                           #:priority 85 #:relevance 1))
                         (begin
                           (emit-answer!
                            'INSUFFICIENT_INFORMATION
                            (string-append
                             "INSUFFICIENT_INFORMATION: the model produced an unverified hypothesis.\n"
                             (co-content co))
                            (co-content co))
                           '())))
                   '())))))

         (execution-processor
          (make-cognitive-processor
           'EXECUTION '(WorkspaceBroadcast)
           (lambda (event)
             (let ((action (event-payload event)))
               (when (and (active-process? session process)
                          (belongs-to-process? action process)
                          (eq? (co-type action) 'action))
                 (session-emit! session 'ActionRequested action #:origin 'CONTROL)
                 (on-client-event `(code ,(co-content action)))
                 (execute
                  (co-content action)
                  (lambda (result-text)
                    (when (active-process? session process)
                      (let ((result
                             (make-cognitive-object
                              'result result-text #:provenance 'REPL
                              #:relations `((process . ,process-id*)
                                            (produced-by . ,(co-id action))))))
                        (on-client-event `(result ,result-text))
                        (session-record-result! session (co-id action) result))))
                  (lambda (error-type error-text)
                    (when (active-process? session process)
                      (let* ((message (string-append
                                       "Runtime Error (" (format #f "~a" error-type) "): "
                                       error-text))
                             (failure
                              (make-cognitive-object
                               'result message #:provenance 'REPL
                               #:relations `((process . ,process-id*)
                                             (produced-by . ,(co-id action))))))
                        (on-client-event `(repl-error ,message))
                        (session-record-failure! session (co-id action) failure))))))
             '()))))

         (deliberative-processor
          (make-cognitive-processor
           'DELIBERATIVE '(ActionCompleted ActionFailed WorkspaceBroadcast)
           (lambda (event)
             (let ((payload (event-payload event)))
               (cond
                ((and (eq? (event-type event) 'ActionCompleted)
                      (active-process? session process)
                      (belongs-to-process? payload process))
                 (let* ((action-id (relation-ref payload 'produced-by))
                        (evidence
                         (make-cognitive-object
                          'evidence
                          (string-append "Execution observed: " (co-content payload))
                          #:provenance 'EXECUTION
                          #:relations `((process . ,process-id*)
                                        (observes . ,(co-id payload))
                                        (produced-by . ,action-id)))))
                   (list (make-processor-proposal evidence
                                                  #:priority 95
                                                  #:relevance 1))))
                ((and (eq? (event-type event) 'ActionFailed)
                      (active-process? session process)
                      (belongs-to-process? payload process))
                 (session-emit! session 'ReflectionRaised payload #:origin 'DELIBERATIVE)
                 (emit-answer! 'FAILED
                               (string-append "GCAS action failed: " (co-content payload))
                               "")
                 '())
                ((and (eq? (event-type event) 'WorkspaceBroadcast)
                      (active-process? session process)
                      (belongs-to-process? payload process)
                      (eq? (co-type payload) 'evidence))
                 (session-emit! session 'EvidenceFound payload #:origin 'DELIBERATIVE)
                 (let ((claim
                        (make-cognitive-object
                         'claim
                         (string-append
                          "The approved action produced the observed REPL output: "
                          (let ((result (state-find
                                         (session-state session)
                                         (relation-ref payload 'observes))))
                            (if result (co-content result) "<missing result>")))
                         #:provenance 'SYMBOLIC_INFERENCE
                         #:epistemic-status 'ACCEPTED
                         #:verification-status 'VERIFIED
                         #:relations `((process . ,process-id*)
                                       (supported-by . ,(co-id payload))
                                       (serves . ,(co-id goal))))))
                   (list (make-processor-proposal claim
                                                  #:priority 100
                                                  #:relevance 1))))
                ((and (eq? (event-type event) 'WorkspaceBroadcast)
                      (active-process? session process)
                      (belongs-to-process? payload process)
                      (eq? (co-type payload) 'claim))
                 (session-emit! session 'BeliefUpdated payload #:origin 'DELIBERATIVE)
                 (session-emit! session 'ReflectionRaised payload #:origin 'DELIBERATIVE)
                 (emit-answer!
                  'INCONCLUSIVE
                  (string-append
                   "INCONCLUSIVE: verified execution observation recorded.\n"
                   (co-content payload)
                   "\nThe original question is not accepted as true without independent evidence.")
                  "")
                 '())
                (else '()))))))

         (answer-processor
          (make-cognitive-processor
           'ANSWER '(AnswerRequested)
           (lambda (event)
             (let ((request (event-payload event)))
               (when (and (active-process? session process)
                          (equal? (assoc-ref request 'process-id) process-id*))
                 (let ((outcome (assoc-ref request 'outcome))
                       (final-text (assoc-ref request 'final-text))
                       (hypothesis-text (assoc-ref request 'hypothesis-text)))
                   (detach!)
                   (when (session-finish-process! session outcome)
                     (on-finished outcome final-text hypothesis-text))))
             '()))))

         (lifecycle-processor
          (make-cognitive-processor
           'CONTROL '(GoalCompleted ProcessTerminated)
           (lambda (event)
             ;; Normal answers detach before finishing. This path also cleans up
             ;; subscriptions when an external interrupt terminates the process.
             (when (eq? (session-current-process session) process)
               (detach!))
             '()))))

      (let ((processors (list scheduler memory-processor generative-processor
                              planner-processor execution-processor
                              deliberative-processor answer-processor
                              lifecycle-processor)))
        (set-car! subscriptions-cell
                  (append-map (lambda (processor)
                                (attach-processor! session processor))
                              processors)))

      (session-submit! session question #:priority 10 #:relevance 1 #:origin 'USER)
      (session-emit! session 'ObservationReceived question #:origin 'USER)
      (session-submit! session goal #:priority 100 #:relevance 1 #:origin 'USER)
      (memory-store! (session-memory session) question)
      (memory-store! (session-memory session) goal)
      (session-emit! session 'GoalCreated goal #:origin 'CONTROL)
      process)))
