(add-to-load-path (string-append (dirname (current-filename)) "/../scheme"))

(use-modules (gaia executor)
             (gaia utils)
             (srfi srfi-64))

(test-begin "gaia-core")

(test-group "utils"
  (test-equal "json conversion"
    "{\"key\":\"value\"}"
    (scm->json '(("key" . "value")))))

(test-group "executor"
  (test-equal "simple calculation"
    "4" ;; Execution output
    (let ((result (guix-investigate "(display (+ 2 2))")))
       result)))

(test-end "gaia-core")
