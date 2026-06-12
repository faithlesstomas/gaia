(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (srfi srfi-64)
             (gaia curator)
             (gaia utils)
             (ice-9 match)
             (ice-9 rdelim)
             (ice-9 hash-table))

(test-begin "gaia-curator")

;; 1. Test private helpers using @@
(test-group "curator-helpers"
  (test-assert "parse-line: valid json"
    (let ((res ((@@ (gaia curator) parse-line) "{\"session_id\":\"123\",\"val\":456}")))
      (and (list? res)
           (equal? (assoc-ref res "session_id") "123")
           (equal? (assoc-ref res "val") 456))))

  (test-assert "parse-line: invalid json"
    (not ((@@ (gaia curator) parse-line) "{invalid json")))

  (test-assert "session-success?: detects true final_signal"
    ((@@ (gaia curator) session-success?)
     '((("final_signal" . "false"))
       (("final_signal" . "true")))))

  (test-assert "session-success?: handles missing final_signal"
    (not ((@@ (gaia curator) session-success?)
          '((("other" . "field"))
            (("final_signal" . "false"))))))

  (test-assert "format-chatml-session: ShareGPT format"
    (let* ((steps '((("input" . "hello") ("response" . "hi"))
                    (("input" . "world") ("response" . "earth"))))
           (formatted ((@@ (gaia curator) format-chatml-session) steps))
           (conversations (vector->list (assoc-ref formatted "conversations"))))
      (and (equal? (length conversations) 4)
           (equal? (assoc-ref (list-ref conversations 0) "from") "human")
           (equal? (assoc-ref (list-ref conversations 0) "value") "hello")
           (equal? (assoc-ref (list-ref conversations 1) "from") "gpt")
           (equal? (assoc-ref (list-ref conversations 1) "value") "hi")))))

;; 2. Test curate-dataset end-to-end
(test-group "curate-dataset-end-to-end"
  (test-assert "correctly splits successes and failures"
    (let* ((input-path "tmp_test_trajectories.jsonl")
           (success-path "tmp_test_success.jsonl")
           (failure-path "tmp_test_failure.jsonl")
           ;; Create mock records:
           ;; Session A: 2 steps, last step has final_signal="true" -> success
           ;; Session B: 1 step, final_signal="false" -> failure
           (rec-a1 "{\"session_id\":\"session-a\",\"input\":\"input-a1\",\"response\":\"resp-a1\",\"final_signal\":\"false\"}")
           (rec-a2 "{\"session_id\":\"session-a\",\"input\":\"input-a2\",\"response\":\"resp-a2\",\"final_signal\":\"true\"}")
           (rec-b1 "{\"session_id\":\"session-b\",\"input\":\"input-b1\",\"response\":\"resp-b1\",\"final_signal\":\"false\"}"))
      
      ;; Write mock trajectory file
      (call-with-output-file input-path
        (lambda (port)
          (display rec-a1 port) (newline port)
          (display rec-a2 port) (newline port)
          (display rec-b1 port) (newline port)))

      ;; Run curator
      (curate-dataset input-path success-path failure-path)

      ;; Read results
      (let* ((success-lines (call-with-input-file success-path (@@ (gaia curator) read-all-lines)))
             (failure-lines (call-with-input-file failure-path (@@ (gaia curator) read-all-lines))))
        
        ;; Clean up temp files
        (delete-file input-path)
        (delete-file success-path)
        (delete-file failure-path)

        ;; Verify expectations
        (and (equal? (length success-lines) 1)
             (equal? (length failure-lines) 1)
             (let* ((succ-rec (json->scm (car success-lines)))
                    (succ-convs (vector->list (assoc-ref succ-rec "conversations")))
                    (fail-rec (json->scm (car failure-lines)))
                    (fail-convs (vector->list (assoc-ref fail-rec "conversations"))))
               (and (equal? (length succ-convs) 4)
                    (equal? (length fail-convs) 2)
                    (equal? (assoc-ref (list-ref succ-convs 0) "value") "input-a1")
                    (equal? (assoc-ref (list-ref fail-convs 0) "value") "input-b1"))))))))

(test-end "gaia-curator")
