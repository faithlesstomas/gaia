(define-module (gaia curator)
  #:use-module (gaia utils)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (ice-9 hash-table)
  #:export (curate-dataset))

(define (read-all-lines port)
  (let loop ((line (read-line port))
             (lines '()))
    (if (eof-object? line)
        (reverse lines)
        (loop (read-line port) (cons line lines)))))

(define (parse-line line)
  (catch #t
    (lambda () (json->scm line))
    (lambda _ #f)))

(define (group-by-session records)
  (let ((sessions (make-hash-table)))
    (for-each (lambda (rec)
                (let* ((sid (assoc-ref rec "session_id"))
                       (existing (hash-ref sessions sid '())))
                  (hash-set! sessions sid (append existing (list rec)))))
              records)
    sessions))

(define (session-success? steps)
  ;; A session is successful if ANY step has final_signal = "true"
  (any (lambda (step) 
         (string=? (or (assoc-ref step "final_signal") "false") "true"))
       steps))

(define (format-chatml-session steps)
  ;; Convert a list of steps into a ShareGPT/ChatML style conversation
  ;; Format: {"conversations": [{"from": "human", "value": "..."}, {"from": "gpt", "value": "..."}]}
  (let ((conversations '()))
    ;; System prompt is implicit in the model, but we can add it if needed.
    ;; For now, we map Input -> Human, Response -> GPT
    
    (define (ensure-string val)
      (cond ((string? val) val)
            ((not val) "")
            (else (format #f "~a" val))))
            
    (define (build-conv steps acc)
      (if (null? steps)
          acc
          (let* ((step (car steps))
                 (input (ensure-string (assoc-ref step "input")))
                 (response (ensure-string (assoc-ref step "response"))))
            (build-conv (cdr steps)
                        (append acc 
                                (list `(("from" . "human") ("value" . ,input))
                                      `(("from" . "gpt") ("value" . ,response))))))))
    
    `(("conversations" . ,(list->vector (build-conv steps '()))))))

(define (curate-dataset input-file output-success output-failure)
  (display "Reading trajectories...\n")
  (let* ((lines (call-with-input-file input-file read-all-lines))
         (records (filter-map parse-line lines))
         (sessions (group-by-session records))
         (success-count 0)
         (failure-count 0))
    
    (display (format #f "Found ~a unique sessions.\n" (hash-count (const #t) sessions)))

    (let ((succ-port (open-file output-success "w"))
          (fail-port (open-file output-failure "w")))
      
      (hash-for-each 
       (lambda (sid steps)
         (if (session-success? steps)
             (begin
               (set! success-count (+ 1 success-count))
               (display (scm->json (format-chatml-session steps)) succ-port)
               (newline succ-port))
             (begin
               (set! failure-count (+ 1 failure-count))
               (display (scm->json (format-chatml-session steps)) fail-port)
               (newline fail-port))))
       sessions)
      
      (close-port succ-port)
      (close-port fail-port)
      
      (display (format #f "Curated: ~a successful sessions, ~a failed sessions.\n"
                       success-count failure-count))
      
      ;; Check for push-to-llm flag (simple check for now)
      (let ((args (command-line)))
        (cond
          ((member "--push-to-llm" args) =>
           (lambda (tail)
             (if (null? (cdr tail))
                 (display "Error: --push-to-llm requires a URL argument.\n")
                 (let ((url (cadr tail)))
                   (display (format #f "Pushing dataset to LLM at ~a...\n" url))
                   ;; Use curl for simplicity
                   (let ((status (system* "curl" "-X" "POST" 
                                          "-F" (string-append "file=@" output-success) 
                                          (string-append url "/train/dataset"))))
                     (if (zero? status)
                         (display "Dataset pushed successfully.\n")
                         (display "Failed to push dataset.\n"))))))))))))

