(define-module (gaia production-processors)
  #:use-module (srfi srfi-1)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-control)
  #:use-module (gaia cognitive-memory)
  #:use-module (gaia cognitive-process)
  #:use-module (gaia cognitive-processor)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia cognitive-state)
  #:use-module (gaia goal-verifier)
  #:export (start-production-process!))

(define (relation-ref co key)
  (and (cognitive-object? co) (assoc-ref (co-relations co) key)))

(define (belongs-to-process? co process)
  (and (cognitive-object? co)
       (or (equal? (relation-ref co 'process) (process-id process))
           (equal? (co-id co) (co-id (process-goal process))))))

(define (active-process? session process)
  (let ((current (session-current-process session)))
    (and current (eq? current process) (process-active? process))))

(define* (answer-request process outcome final-text hypothesis-text
                         #:key (verified-claim #f))
  `((process-id . ,(process-id process))
    (outcome . ,outcome)
    (final-text . ,final-text)
    (hypothesis-text . ,hypothesis-text)
    (verified-claim . ,(and verified-claim (co-id verified-claim)))))

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
          (max-failures 3)
          (max-replans 3)
          (verify-goal default-goal-verifier))
  "Start one bounded, recurrent production cognitive process.

GENERATE accepts PROMPT, SUCCESS and FAILURE callbacks. EXECUTE accepts ACTION
text, SUCCESS and FAILURE callbacks.  Processors only communicate through the
Cognitive Bus and Workspace rounds; the adapters keep this process independent
from Goblins actors and a particular LLM/runtime."
  (unless (and (cognitive-session? session) (string? task)
               (procedure? generate) (procedure? execute)
               (procedure? extract-action) (procedure? on-client-event)
               (procedure? on-finished) (procedure? verify-goal)
               (integer? max-replans) (>= max-replans 0))
    (error "Invalid production process adapters or replan budget" session task))
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
         (hypothesis-text-cell (list ""))
         (replan-count-cell (list 0))
         (generative-processor-cell (list #f))
         ;; A request made while a broadcast is being handled is deferred.  This
         ;; preserves a true proposal batch and releases the current focus before
         ;; the next round, avoiding nested admissions and capacity leaks.
         (round-running-cell (list #f))
         (round-requested-cell (list #f)))

    (define* (emit-answer! outcome final-text hypothesis-text #:key (verified-claim #f))
      (when (active-process? session process)
        (session-emit! session 'AnswerRequested
                       (answer-request
                        process outcome final-text
                        (if (> (string-length hypothesis-text) 0)
                            hypothesis-text
                            (car hypothesis-text-cell))
                        #:verified-claim verified-claim)
                       #:origin 'CONTROL)))

    (define (detach!)
      (for-each (lambda (subscription)
                  (bus-unsubscribe (session-bus session) subscription))
                (car subscriptions-cell))
      (set-car! subscriptions-cell '()))

    (define (request-round!)
      "Mark a completed proposal batch ready, then drain pending rounds.
One call admits one winner from every then-pending batch; callbacks produced
during a broadcast set the flag for a subsequent round."
      (when (active-process? session process)
        (set-car! round-requested-cell #t)
        (unless (car round-running-cell)
          (set-car! round-running-cell #t)
          (let loop ()
            (when (and (active-process? session process)
                       (car round-requested-cell))
              (set-car! round-requested-cell #f)
              (session-run-workspace-round! session)
              (when (car round-requested-cell) (loop)))
          (set-car! round-running-cell #f)))))

    (define (replan-context feedback)
      (reconstruct-context
       goal
       (list feedback)
       (memory-retrieve (session-memory session) task)
       #:constraints
       (list completion-criteria
             "Previous execution feedback is evidence, not an answer."
             "Revise the plan and propose a distinct Action when appropriate."
             "Treat model output as an unverified hypothesis.")))

    (define (generate-hypothesis! prompt replanning?)
      (generate
       prompt
       (lambda (response-text)
         (when (active-process? session process)
           ;; A response generated from explicit execution feedback is an
           ;; observable change of strategy, not another stalled transition.
           (when replanning?
             (control-record-progress! (session-control session)))
           (set-car! hypothesis-text-cell response-text)
           (submit-processor-proposal!
            session (car generative-processor-cell)
            (make-processor-proposal
             (make-cognitive-object
              'hypothesis response-text #:provenance 'LLM
              #:relations `((process . ,process-id*)
                            (addresses . ,(co-id goal))))
             #:priority 70 #:relevance 1 #:uncertainty 1))
           (request-round!)))
       (lambda (error-text)
         (emit-answer! 'FAILED
                       (string-append "GCAS generative processor failed: " error-text)
                       ""))))

    (letrec
        ((memory-processor
          (make-cognitive-processor
           'MEMORY '(GoalCreated)
           (lambda (event)
             (let ((event-goal (event-payload event)))
               (if (and (active-process? session process)
                        (cognitive-object? event-goal)
                        (equal? (co-id event-goal) (co-id goal)))
                   (let* ((selected (memory-retrieve (session-memory session) task))
                          (context (reconstruct-context
                                    goal '() selected
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
                                                    #:priority 80 #:relevance 1)))
                   '())))))

         (generative-processor
          (make-cognitive-processor
           'GENERATIVE '(WorkspaceBroadcast)
           (lambda (event)
             (let ((co (event-payload event)))
               (cond
                ((and (active-process? session process)
                      (belongs-to-process? co process)
                      (eq? (co-type co) 'observation)
                      (relation-ref co 'context-for))
                 (generate-hypothesis! (co-content co) #f))
                ((and (active-process? session process)
                      (belongs-to-process? co process)
                      (eq? (co-type co) 'reflection)
                      (relation-ref co 'replan))
                 (if (< (car replan-count-cell) max-replans)
                     (begin
                       (set-car! replan-count-cell (+ 1 (car replan-count-cell)))
                       (generate-hypothesis! (replan-context co) #t))
                     (emit-answer!
                      'FAILED
                      "FAILED: the cognitive process exhausted its replanning budget."
                      "")))
                (else #f))
             '()))))

         (planner-processor
          (make-cognitive-processor
           'PLANNER '(WorkspaceBroadcast)
           (lambda (event)
             (let ((co (event-payload event)))
               (cond
                ((and (active-process? session process)
                      (belongs-to-process? co process)
                      (eq? (co-type co) 'hypothesis))
                 (let ((action-text (extract-action (co-content co))))
                   (session-emit! session 'HypothesisProposed co #:origin 'GENERATIVE)
                   (if action-text
                       (list
                        (make-processor-proposal
                         (make-cognitive-object
                          'plan
                          `((action . ,action-text)
                            (verification . "Record a reproducible execution observation."))
                          #:provenance 'LLM
                          #:relations `((process . ,process-id*)
                                        (based-on . ,(co-id co))
                                        (serves . ,(co-id goal))))
                         #:priority 90 #:relevance 1 #:uncertainty 1))
                       (begin
                         (emit-answer!
                          'INSUFFICIENT_INFORMATION
                          "INSUFFICIENT_INFORMATION: no executable, independently verifiable plan was proposed."
                          "")
                         '()))))
                ((and (active-process? session process)
                      (belongs-to-process? co process)
                      (eq? (co-type co) 'plan))
                 (session-emit! session 'PlanProposed co #:origin 'PLANNER)
                 (let ((action-text (assoc-ref (co-content co) 'action)))
                   (if (string? action-text)
                       (let ((subgoal
                              (make-cognitive-object
                               'goal
                               (string-append "Verify the execution observation for: " action-text)
                               #:provenance 'SYMBOLIC_INFERENCE
                               #:relations `((process . ,process-id*)
                                             (parent-goal . ,(co-id goal))
                                             (implemented-by . ,(co-id co))))))
                         ;; GCAS models subgoals as linked Goal COs, rather than
                         ;; giving them an untyped side channel in a Plan.
                         (state-store! (session-state session) subgoal)
                         (session-emit! session 'GoalCreated subgoal #:origin 'PLANNER)
                         (list
                          (make-processor-proposal
                           (make-cognitive-object
                            'action action-text #:provenance 'LLM
                            #:relations `((process . ,process-id*)
                                          (implements . ,(co-id co))
                                          (serves . ,(co-id goal))
                                          (advances . ,(co-id subgoal))))
                           #:priority 85 #:relevance 1)
                          (make-processor-proposal subgoal #:priority 60 #:relevance 1)))
                       (begin
                         (emit-answer! 'FAILED "FAILED: Planner produced a Plan without an Action." "")
                         '()))))
                ((and (active-process? session process)
                      (belongs-to-process? co process)
                      (eq? (co-type co) 'reflection)
                      (not (relation-ref co 'replan)))
                 (emit-answer!
                  'INCONCLUSIVE
                  (string-append
                   "INCONCLUSIVE: the Goal verifier could not establish completion.\n"
                   (co-content co)
                   "\nNo unverified model output is presented as the answer.")
                  "")
                 '())
                (else '()))))))

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
           'DELIBERATIVE '(ActionCompleted ActionFailed ConflictDetected WorkspaceBroadcast)
           (lambda (event)
             (let ((payload (event-payload event)))
               (cond
                ((and (eq? (event-type event) 'ActionCompleted)
                      (active-process? session process)
                      (belongs-to-process? payload process))
                 (let ((evidence
                        (make-cognitive-object
                         'evidence
                         (string-append "Execution observed: " (co-content payload))
                         #:provenance 'EXECUTION
                         #:relations `((process . ,process-id*)
                                       (observes . ,(co-id payload))
                                       (produced-by . ,(relation-ref payload 'produced-by))))))
                   (list (make-processor-proposal evidence #:priority 95 #:relevance 1))))
                ((and (memq (event-type event) '(ActionFailed ConflictDetected))
                      (active-process? session process)
                      (belongs-to-process? payload process))
                 (let ((reflection
                        (make-cognitive-object
                         'reflection
                         (string-append "Feedback requires replanning: " (co-content payload))
                         #:provenance 'SYMBOLIC_INFERENCE
                         #:relations `((process . ,process-id*)
                                       (replan . #t)
                                       (feedback-for . ,(co-id goal))
                                       (based-on . ,(co-id payload))))))
                   (session-emit! session 'ReflectionRaised reflection #:origin 'DELIBERATIVE)
                   (list (make-processor-proposal reflection #:priority 100 #:relevance 1))))
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
                          (let ((result (state-find (session-state session)
                                                    (relation-ref payload 'observes))))
                            (if result (co-content result) "<missing result>")))
                         #:provenance 'SYMBOLIC_INFERENCE
                         #:epistemic-status 'ACCEPTED
                         #:verification-status 'VERIFIED
                         #:relations `((process . ,process-id*)
                                       (supported-by . ,(co-id payload))
                                       (serves . ,(co-id goal))))))
                   (list (make-processor-proposal claim #:priority 100 #:relevance 1))))
                ((and (eq? (event-type event) 'WorkspaceBroadcast)
                      (active-process? session process)
                      (belongs-to-process? payload process)
                      (eq? (co-type payload) 'claim))
                 (session-emit! session 'BeliefUpdated payload #:origin 'DELIBERATIVE)
                 '())
                ((and (eq? (event-type event) 'WorkspaceBroadcast)
                      (active-process? session process)
                      (belongs-to-process? payload process)
                      (eq? (co-type payload) 'conflict))
                 ;; The conflict is already durable because it reached the
                 ;; Workspace.  Emit its semantic event, then let this same
                 ;; processor turn the event into a feedback Reflection.
                 (session-emit! session 'ConflictDetected payload #:origin 'GOAL_VERIFIER)
                 '())
                (else '()))))))

         (goal-verifier-processor
          (make-cognitive-processor
           'GOAL_VERIFIER '(BeliefUpdated)
           (lambda (event)
             (let ((claim (event-payload event)))
               (if (and (active-process? session process)
                        (belongs-to-process? claim process)
                        (eq? (co-type claim) 'claim)
                        (relation-ref claim 'serves)
                        (not (relation-ref claim 'satisfies)))
                   (let* ((evidence (state-find (session-state session)
                                                (relation-ref claim 'supported-by)))
                          (result (and evidence
                                       (state-find (session-state session)
                                                   (relation-ref evidence 'observes))))
                          (action (and evidence
                                       (state-find (session-state session)
                                                   (relation-ref evidence 'produced-by)))))
                     (if (and evidence result action)
                         (let ((verdict (call-goal-verifier
                                         verify-goal goal action result evidence claim
                                         (session-state session))))
                           (session-emit!
                            session 'GoalVerificationCompleted
                            `((process-id . ,process-id*)
                              (goal . ,(co-id goal))
                              (claim . ,(co-id claim))
                              (status . ,(goal-verdict-status verdict))
                              (rationale . ,(goal-verdict-rationale verdict)))
                            #:origin 'GOAL_VERIFIER)
                           (case (goal-verdict-status verdict)
                             ((SATISFIED)
                              (list
                               (make-processor-proposal
                                (make-cognitive-object
                                 'claim (goal-verdict-claim-content verdict)
                                 #:provenance 'SYMBOLIC_INFERENCE
                                 #:epistemic-status 'ACCEPTED
                                 #:verification-status 'VERIFIED
                                 #:relations `((process . ,process-id*)
                                               (satisfies . ,(co-id goal))
                                               (supported-by . ,(co-id claim))
                                               (verdict-rationale . ,(goal-verdict-rationale verdict))))
                                #:priority 100 #:relevance 1)))
                             ((REJECTED)
                              (list
                               (make-processor-proposal
                                (make-cognitive-object
                                 'conflict
                                 (string-append "Goal verifier rejected execution evidence: "
                                                (goal-verdict-rationale verdict))
                                 #:provenance 'SYMBOLIC_INFERENCE
                                 #:relations `((process . ,process-id*)
                                               (contradicts . ,(co-id claim))
                                               (goal . ,(co-id goal))
                                               (evidence . ,(co-id evidence))))
                                #:priority 100 #:relevance 1)))
                             ((INCONCLUSIVE)
                              (let ((reflection
                                     (make-cognitive-object
                                      'reflection
                                      (goal-verdict-rationale verdict)
                                      #:provenance 'SYMBOLIC_INFERENCE
                                      #:relations `((process . ,process-id*)
                                                    (replan . #f)
                                                    (feedback-for . ,(co-id goal))
                                                    (based-on . ,(co-id claim))))))
                                (session-emit! session 'ReflectionRaised reflection
                                               #:origin 'GOAL_VERIFIER)
                                (list (make-processor-proposal
                                       reflection #:priority 100 #:relevance 1))))))
                         (begin
                           (emit-answer! 'FAILED
                                         "FAILED: Goal verifier received an incomplete execution evidence chain."
                                         "")
                           '())))
                   '())))))

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
                           (equal? (relation-ref claim 'satisfies) (co-id goal)))))
               (let ((claim (event-payload event)))
                 (session-emit! session 'GoalVerified claim #:origin 'GOAL_VERIFIER)
                 (emit-answer!
                  'COMPLETED
                  (string-append "COMPLETED: " (co-content claim)
                                 "\nVerification: "
                                 (or (relation-ref claim 'verdict-rationale)
                                     "independent Goal verifier accepted the evidence."))
                  ""
                  #:verified-claim claim))
               '())
              ((eq? (event-type event) 'AnswerRequested)
               (let ((request (event-payload event)))
                 (when (and (active-process? session process)
                            (equal? (assoc-ref request 'process-id) process-id*))
                   (let ((outcome (assoc-ref request 'outcome))
                         (final-text (assoc-ref request 'final-text))
                         (hypothesis-text (assoc-ref request 'hypothesis-text))
                         (verified-claim (and (assoc-ref request 'verified-claim)
                                              (state-find (session-state session)
                                                          (assoc-ref request 'verified-claim)))))
                     (detach!)
                     (if (eq? outcome 'COMPLETED)
                         (when (session-complete-goal! session verified-claim)
                           (on-finished outcome final-text hypothesis-text))
                         (when (session-finish-process! session outcome)
                           (on-finished outcome final-text hypothesis-text))))))
               '())
              (else '())))))

         (lifecycle-processor
          (make-cognitive-processor
           'CONTROL '(GoalCompleted ProcessTerminated)
           (lambda (event)
             (when (eq? (session-current-process session) process) (detach!))
             '()))))

      (let ((processors (list memory-processor generative-processor planner-processor
                              execution-processor deliberative-processor goal-verifier-processor answer-processor
                              lifecycle-processor)))
        (set-car! generative-processor-cell generative-processor)
        (set-car! subscriptions-cell
                  (append-map (lambda (processor)
                                (attach-processor! session processor
                                                   #:after-submit request-round!))
                              processors)))

      ;; Initial producers submit as one batch.  GoalCreated lets Memory add a
      ;; context proposal before Control starts the first competition round.
      (session-submit! session question #:priority 10 #:relevance 1 #:origin 'USER)
      (session-emit! session 'ObservationReceived question #:origin 'USER)
      (session-submit! session goal #:priority 100 #:relevance 1 #:origin 'USER)
      (memory-store! (session-memory session) question)
      (memory-store! (session-memory session) goal)
      (session-emit! session 'GoalCreated goal #:origin 'CONTROL)
      (request-round!)
      process)))
