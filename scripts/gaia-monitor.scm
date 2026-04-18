#!/usr/bin/env guile
-s
!#
;;; gaia-monitor.scm — Real-time Thought Monitor for GAIA
;;;
;;; Tails trajectories.jsonl and displays model's reasoning, code and results.
;;; Use: guile -L scheme scripts/gaia-monitor.scm

(add-to-load-path (string-append (dirname (current-filename)) "/../scheme"))

(use-modules (gaia utils)
             (ice-9 rdelim)
             (ice-9 match)
             (ice-9 format)
             (ice-9 string-fun))

(define C-RESET "\x1b[0m")
(define C-BOLD "\x1b[1m")
(define C-RED "\x1b[31m")
(define C-GREEN "\x1b[32m")
(define C-YELLOW "\x1b[33m")
(define C-BLUE "\x1b[34m")
(define C-CYAN "\x1b[36m")
(define C-GREY "\x1b[90m")

(define (print-header title color)
  (display (string-append color C-BOLD "\n=== " title " ===" C-RESET "\n")))

(define (format-json-entry entry)
  (let ((type (assoc-ref entry "type"))
        (session-id (assoc-ref entry "session_id"))
        (timestamp (assoc-ref entry "timestamp")))

    (cond
     ;; 1. Interaction log (Thought process)
     ((not type)
      (let ((response (assoc-ref entry "response"))
            (reasoning (assoc-ref entry "reasoning"))
            (confidence (assoc-ref entry "confidence")))
        (print-header (string-append "MONOLOG [" session-id "]") C-CYAN)
        
        ;; 1. Display Reasoning (if present)
        (when (and (string? reasoning) (not (string-null? reasoning)))
          (display (string-append C-GREY "\n[THOUGHT PROCESS START]\n" C-RESET))
          (display reasoning)
          (display (string-append C-GREY "\n[THOUGHT PROCESS END]\n" C-RESET))
          (newline))

        ;; 2. Display Response (with fallback tag formatting)
        (let* ((text (string-replace-substring response "<channel|>" (string-append C-GREY "[CHANNEL SW]" C-RESET)))
               (text (string-replace-substring text "<unused87>tool_code\n" ""))
               (text (string-replace-substring text "<unused87>tool_code" ""))
               (text (string-replace-substring text "<unused88>\n" ""))
               (text (string-replace-substring text "<unused88>" ""))
               (text (string-replace-substring text "<|think|>" (string-append C-BOLD C-CYAN "[ACTIVATE THINKING]" C-RESET)))
               (text (string-replace-substring text "<thought>" (string-append C-GREY "\n[THOUGHT START]\n" C-RESET)))
               (text (string-replace-substring text "</thought>" (string-append C-GREY "\n[THOUGHT END]\n" C-RESET))))
          (display text)
          (newline))
        
        (when confidence
          (display (string-append C-GREY "Confidence: " (format #f "~a" confidence) "%" C-RESET "\n")))))

     ;; 2. Execution log (Code and result)
     ((string=? type "execution")
      (let ((code (assoc-ref entry "code"))
            (result (assoc-ref entry "result"))
            (status (assoc-ref entry "status")))
        (print-header (string-append "EXECUTION [" session-id "]") C-YELLOW)
        (display (string-append C-BOLD "CODE:" C-RESET "\n"))
        (display (string-append C-BLUE code C-RESET "\n"))
        (display (string-append C-BOLD "RESULT (" status "):" C-RESET "\n"))
        (if (string=? status "success")
            (display (string-append C-GREEN result C-RESET "\n"))
            (display (string-append C-RED result C-RESET "\n")))))

     (else
      (display (string-append C-GREY "Unknown entry type: " (or type "null") C-RESET "\n"))))))

(define (tail-log path)
  (if (not (file-exists? path))
      (begin
        (display (string-append "Waiting for " path " to be created...\n"))
        (let loop ()
          (if (file-exists? path)
              (tail-log path)
              (begin (sleep 1) (loop)))))
      (begin
        (display (string-append C-BOLD "Monitoring GAIA Trajectories: " path C-RESET "\n"))
        (let ((port (open-file path "r")))
          ;; Seek to end if you only want new entries, but here we show everything first?
          ;; Let's show from start for now, or use a flag.
          (let loop ()
            (let ((line (read-line port)))
              (if (eof-object? line)
                  (begin
                    (sleep 1) ;; Wait for new data
                    (loop))
                  (begin
                    (catch #t
                      (lambda ()
                        (let ((entry (json->scm line)))
                          (format-json-entry entry)))
                      (lambda (key . args)
                        (display (string-append C-RED "Parse Error: " (format #f "~a" key) C-RESET "\n"))))
                    (loop)))))))))

(define (get-log-path)
  (let ((args (command-line)))
    ;; args[0] is the script name, args[1] would be the first real arg
    (if (> (length args) 1)
        (list-ref args 1)
        "trajectories.jsonl")))

(tail-log (get-log-path))
