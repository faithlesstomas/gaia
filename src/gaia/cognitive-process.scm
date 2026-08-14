(define-module (gaia cognitive-process)
  #:use-module (srfi srfi-9)
  #:use-module (gaia com)
  #:use-module (gaia cognitive-control)
  #:export (<cognitive-process>
            make-cognitive-process
            cognitive-process?
            process-id
            process-goal
            process-completion-criteria
            process-control
            process-status
            process-outcome
            process-started-at
            process-ended-at
            process-active?
            process-finish!))

;; A Cognitive Process is the runtime lifecycle of one Goal. Durable facts about
;; it are represented by the Goal and terminal events in Cognitive State; this
;; record owns the live scheduling budget and exactly-once terminal transition.
(define-record-type <cognitive-process>
  (%make-process id goal completion-criteria control status-cell outcome-cell
                 started-at ended-at-cell)
  cognitive-process?
  (id process-id)
  (goal process-goal)
  (completion-criteria process-completion-criteria)
  (control process-control)
  (status-cell process-status-cell)
  (outcome-cell process-outcome-cell)
  (started-at process-started-at)
  (ended-at-cell process-ended-at-cell))

(define* (make-cognitive-process goal completion-criteria
                                 #:key
                                 (max-transitions 32)
                                 (max-stalled-transitions 8)
                                 (max-failures 3))
  (unless (and (cognitive-object? goal)
               (eq? (co-type goal) 'goal)
               (string? completion-criteria)
               (positive? (string-length completion-criteria)))
    (error "A Cognitive Process requires a Goal CO and completion criteria"
           goal completion-criteria))
  (%make-process
   (string-append "process-" (co-id goal))
   goal
   completion-criteria
   (make-cognitive-control #:max-transitions max-transitions
                           #:max-stalled-transitions max-stalled-transitions
                           #:max-failures max-failures)
   (list 'ACTIVE)
   (list #f)
   (current-time)
   (list #f)))

(define (process-status process)
  (car (process-status-cell process)))

(define (process-outcome process)
  (car (process-outcome-cell process)))

(define (process-ended-at process)
  (car (process-ended-at-cell process)))

(define (process-active? process)
  (and (cognitive-process? process)
       (eq? (process-status process) 'ACTIVE)))

(define (process-finish! process outcome)
  "Atomically move PROCESS to its sole terminal state. Return #f for duplicate
completion attempts so late asynchronous callbacks cannot emit another outcome."
  (if (not (process-active? process))
      #f
      (begin
        (set-car! (process-status-cell process) 'TERMINATED)
        (set-car! (process-outcome-cell process) outcome)
        (set-car! (process-ended-at-cell process) (current-time))
        outcome)))
