(add-to-load-path (string-append (dirname (current-filename)) "/../src"))
(use-modules (srfi srfi-64)
             (ice-9 match)
             (ice-9 threads)
             (gaia server))

(test-begin "gaia-hitl-sync")

(test-assert "operation-matches-scopes? works"
  (let ((scopes '((always . (run-command "ls"))
                  (directory . "/workspace/safe"))))
    (and ((@@ (gaia server) operation-matches-scopes?) '(run-command "ls") scopes)
         (not ((@@ (gaia server) operation-matches-scopes?) '(run-command "rm") scopes))
         ((@@ (gaia server) operation-matches-scopes?) '(write-file "/workspace/safe/file.txt" "hello") scopes)
         (not ((@@ (gaia server) operation-matches-scopes?) '(write-file "/workspace/unsafe/file.txt" "hello") scopes)))))

(test-end "gaia-hitl-sync")
