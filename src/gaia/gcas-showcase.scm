(define-module (gaia gcas-showcase)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia cognitive-state)
  #:use-module (gaia cognitive-bus)
  #:export (run-gcas-reference-cycle
            showcase-summary))

;; A deliberately narrow, executable reference cycle for GCAS-Core.  It is not
;; the legacy RLM loop and does not depend on an LLM call.  Production execution
;; is supplied through an Action executor; the default executes one fixed,
;; deterministic Guile expression used by the public showcase.

(define (default-executor action-co)
  (let ((code (co-content action-co)))
    (if (string=? code "(+ 20 22)")
        (catch #t
          (lambda ()
            `((status . ok)
              (output . ,(format #f "~a"
                                  (eval (with-input-from-string code read)
                                        (interaction-environment))))))
          (lambda (key . args)
            `((status . failed)
              (output . ,(format #f "~a" args)))))
        '((status . failed) (output . "Action rejected by showcase executor")))))

(define (admit! session co priority origin semantic-event)
  (session-submit! session co #:priority priority #:origin origin)
  (let ((admitted (session-advance! session)))
    (unless admitted
      (error "Workspace could not admit showcase object" (co-id co)))
    (session-emit! session semantic-event co #:origin origin)
    (session-release-workspace-object! session (co-id admitted))
    co))

(define (linked type content provenance relation-type relation-id)
  (make-cognitive-object type content
                         #:provenance provenance
                         #:relations `((,relation-type . ,relation-id))))

(define (showcase-summary session outcome claim)
  `((outcome . ,outcome)
    (claim . ,claim)
    (objects . ,(state-objects (session-state session)))
    (events . ,(state-events (session-state session)))))

(define* (run-gcas-reference-cycle #:key
                                   (executor default-executor)
                                   (expected-output "42")
                                   (workspace-capacity 3)
                                   (max-transitions 32))
  "Run the GCAS-Core reference scenario for the claim that (+ 20 22) returns 42.

EXECUTOR receives an Action CO and returns an alist containing status (ok or
failed) and output.  Tests can inject conflicting evidence without replacing
the cognitive process itself."
  (let* ((session (make-cognitive-session #:workspace-capacity workspace-capacity
                                           #:max-transitions max-transitions))
         (question (make-cognitive-object 'question
                                          "Does the Guile expression (+ 20 22) evaluate to 42?"
                                          #:provenance 'USER))
         (goal (linked 'goal "Establish the result of (+ 20 22) with executable evidence"
                       'USER 'answers (co-id question)))
         (memory (linked 'evidence "Arithmetic evaluation requires an executable observation."
                         'MEMORY 'relevant-to (co-id goal)))
         (hypothesis (linked 'hypothesis "(+ 20 22) evaluates to 42."
                             'LLM 'addresses (co-id goal)))
         (action (linked 'action "(+ 20 22)" 'LLM 'tests (co-id hypothesis))))
    ;; Question, goal, retrieval, and generative hypothesis.
    (admit! session question 90 'USER 'ObservationReceived)
    (admit! session goal 100 'CONTROL 'GoalCreated)
    (admit! session memory 40 'MEMORY 'MemoryRetrieved)
    (admit! session hypothesis 80 'LLM 'HypothesisProposed)
    ;; Proposal is distinct from deployment: only this explicit Action reaches
    ;; an executor after workspace admission.
    (admit! session action 85 'CONTROL 'ActionRequested)
    (let* ((execution (executor action))
           (status (assoc-ref execution 'status))
           (output (assoc-ref execution 'output)))
      (if (eq? status 'ok)
          (let* ((result (linked 'result output 'REPL 'produced-by (co-id action)))
                 (_recorded (session-record-result! session (co-id action) result))
                 (evidence (linked 'evidence
                                   (string-append "Executor observed output: " output)
                                   'EXECUTION 'supports (co-id hypothesis))))
            (admit! session evidence 95 'DELIBERATIVE 'EvidenceFound)
            (if (string=? output expected-output)
                (let* ((claim (make-cognitive-object 'claim
                                                      "(+ 20 22) evaluates to 42 in the observed Guile runtime."
                                                      #:provenance 'SYMBOLIC_INFERENCE
                                                      #:epistemic-status 'ACCEPTED
                                                      #:verification-status 'VERIFIED
                                                      #:confidence 1.0
                                                      #:relations `((supported-by . ,(co-id evidence))
                                                                    (derived-from . ,(co-id hypothesis)))) )
                       (_stored (admit! session claim 100 'DELIBERATIVE 'BeliefUpdated))
                       (reflection (linked 'reflection
                                           "The hypothesis was confirmed only for the observed runtime expression."
                                           'SYMBOLIC_INFERENCE 'about (co-id claim))))
                  (admit! session reflection 30 'METACOGNITION 'ReflectionRaised)
                  (session-emit! session 'GoalCompleted goal #:origin 'CONTROL)
                  (showcase-summary session 'CONFIRMED claim))
                (let* ((conflict (make-cognitive-object 'conflict
                                                        (string-append "Expected " expected-output ", observed " output)
                                                        #:provenance 'EXECUTION
                                                        #:relations `((contradicts . ,(co-id hypothesis))
                                                                      (evidence . ,(co-id evidence)))) )
                       (_stored (admit! session conflict 100 'DELIBERATIVE 'ConflictDetected))
                       (reflection (linked 'reflection
                                           "Evidence conflicts with the generated hypothesis; no belief was accepted."
                                           'SYMBOLIC_INFERENCE 'about (co-id conflict))))
                  (admit! session reflection 30 'METACOGNITION 'ReflectionRaised)
                  (session-emit! session 'ProcessTerminated 'CONFLICTING_EVIDENCE #:origin 'CONTROL)
                  (showcase-summary session 'CONFLICTING_EVIDENCE #f))))
          (let* ((failure (linked 'result output 'REPL 'produced-by (co-id action)))
                 (_recorded (session-record-failure! session (co-id action) failure))
                 (reflection (linked 'reflection
                                     "Execution failed; the hypothesis remains unverified."
                                     'SYMBOLIC_INFERENCE 'about (co-id failure))))
            (admit! session reflection 30 'METACOGNITION 'ReflectionRaised)
            (session-emit! session 'ProcessTerminated 'FAILED #:origin 'CONTROL)
            (showcase-summary session 'FAILED #f))))))
