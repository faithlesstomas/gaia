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

(define (parameter-ref parameters key)
  (let ((entry (or (assoc key parameters)
                   (assoc (symbol->string key) parameters))))
    (and entry (cdr entry))))

(define (calibrated-reconstruction-error? obs)
  (eq? #t (parameter-ref (obs-parameters obs)
                         'reconstruction-error-calibrated)))

(define* (jspace-observation->proposal obs #:key (base-priority 1) (goal #f))
  "Convert an <ncsi-neural-observation> into a <processor-proposal> for the Global Workspace."
  (unless (ncsi-neural-observation? obs)
    (error "jspace-observation->proposal requires <ncsi-neural-observation>" obs))
  (let* ((concepts (obs-concepts obs))
         ;; Max concept activation score in [0.0, 1.0]
         (max-score (if (null? concepts)
                        0.0
                        (apply max (map concept-score concepts))))
         ;; Reconstruction error is usable as uncertainty only when the
         ;; producer explicitly declares it calibrated.  RAI currently emits
         ;; 0.0 as unavailable metadata; treating that placeholder as perfect
         ;; certainty would let an observation dominate Workspace competition.
         (rec-err (obs-reconstruction-error obs))
         (uncertainty (if (calibrated-reconstruction-error? obs)
                          (min 1.0 (max 0.0 rec-err))
                          1.0))
         ;; Relevance is estimated from concept confidence
         (relevance (min 1.0 (max 0.0 max-score)))
         ;; Cognitive Object with NEURAL_J_LENS provenance
         ;; This confidence is readout strength, not epistemic truth.  The
         ;; neural provenance invariant still forbids ACCEPTED/VERIFIED.
         (obs-co (observation->cognitive-object obs #:confidence relevance))
         (priority base-priority))
    (make-processor-proposal
     obs-co
     #:priority priority
     #:relevance relevance
     #:risk 0.0
     #:cost 0.0
     #:uncertainty uncertainty)))

(define* (make-jspace-processor #:key (base-priority 1) (max-proposals 64))
  "Construct the J-space Cognitive Processor.
Subscribes to NeuralStateObserved events on the Cognitive Bus, transforms neural
activation readouts into Observation Cognitive Objects, and proposes them to the
Global Workspace."
  (unless (and (integer? max-proposals) (> max-proposals 0))
    (error "max-proposals must be a positive integer" max-proposals))
  (let ((counts-cell (list '()))
        (seen-cell (list '())))
    (define (observation-key obs)
      (list (obs-request-id obs) (obs-forward-pass-id obs) (obs-layer obs)))
    (define (admit-observation obs)
      (let* ((request-id (obs-request-id obs))
             (count (or (assoc-ref (car counts-cell) request-id) 0))
             (key (observation-key obs)))
        (if (or (>= count max-proposals)
                (member key (car seen-cell)))
            '()
            (begin
              (set-car! counts-cell
                        (acons request-id (+ count 1)
                               (alist-delete request-id (car counts-cell))))
              (set-car! seen-cell (cons key (car seen-cell)))
              (list (jspace-observation->proposal
                     obs #:base-priority base-priority))))))
    (make-cognitive-processor
     jspace-processor-id
     '(NeuralStateObserved)
     (lambda (event)
       (let ((payload (event-payload event)))
         (cond
          ((ncsi-neural-observation? payload)
           (admit-observation payload))
          ((ncsi-event? payload)
           (if (eq? (ncsi-event-type payload) 'NeuralStateObserved)
               (admit-observation (ncsi-event-payload payload))
               '()))
          ;; Session audit events persist the transport-independent wire alist.
          ;; Re-parse it here so the processor accepts both direct in-process
          ;; events and durable/replayed events without trusting raw data.
          ((list? payload)
           (let ((ncsi-evt (parse-ncsi-event payload)))
             (if (eq? (ncsi-event-type ncsi-evt) 'NeuralStateObserved)
                 (admit-observation (ncsi-event-payload ncsi-evt))
                 '())))
          (else
           '())))))))
