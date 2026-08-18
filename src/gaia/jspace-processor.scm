(define-module (gaia jspace-processor)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-bus)
  #:use-module (gaia cognitive-processor)
  #:use-module (gaia cognitive-session)
  #:use-module (gaia ncsi)
  #:export (make-jspace-processor
            jspace-observation->proposal
            jspace-processor-id))

(define jspace-processor-id 'JSPACE_PROCESSOR)

(define* (jspace-observation->proposal obs #:key (base-priority 5) (goal #f))
  "Convert an <ncsi-neural-observation> into a <processor-proposal> for the Global Workspace."
  (unless (ncsi-neural-observation? obs)
    (error "jspace-observation->proposal requires <ncsi-neural-observation>" obs))
  (let* ((concepts (obs-concepts obs))
         ;; Max concept activation score in [0.0, 1.0]
         (max-score (if (null? concepts)
                        0.0
                        (apply max (map concept-score concepts))))
         ;; Reconstruction error penalizes certainty
         (rec-err (obs-reconstruction-error obs))
         (uncertainty (min 1.0 (max 0.0 rec-err)))
         ;; Relevance is estimated from concept confidence
         (relevance (min 1.0 (max 0.0 max-score)))
         ;; Cognitive Object with NEURAL_J_LENS provenance
         (obs-co (observation->cognitive-object obs #:confidence (max 0.0 (- 1.0 uncertainty))))
         (priority base-priority))
    (make-processor-proposal
     obs-co
     #:priority priority
     #:relevance relevance
     #:risk 0.0
     #:cost 0.0
     #:uncertainty uncertainty)))

(define* (make-jspace-processor #:key (base-priority 5))
  "Construct the J-space Cognitive Processor.
Subscribes to NeuralStateObserved events on the Cognitive Bus, transforms neural
activation readouts into Observation Cognitive Objects, and proposes them to the
Global Workspace."
  (make-cognitive-processor
   jspace-processor-id
   '(NeuralStateObserved)
   (lambda (event)
     (let ((payload (event-payload event)))
       (cond
        ((ncsi-neural-observation? payload)
         (list (jspace-observation->proposal payload #:base-priority base-priority)))
        ((ncsi-event? payload)
         (if (eq? (ncsi-event-type payload) 'NeuralStateObserved)
             (list (jspace-observation->proposal (ncsi-event-payload payload) #:base-priority base-priority))
             '()))
        (else
         '()))))))
