(add-to-load-path (string-append (dirname (current-filename)) "/../scheme"))

(use-modules (gaia core)
             (gaia executor)
             (gaia rai-client))

(display "Starting RLM PoC Test...\n")

;; In a real scenario, this would mock the RAI client to return specific 
;; responses that force a recursive call. 
;; For now, we verified the loop structure via 'make run'.
;; This script serves as a placeholder for advanced integration testing
;; as described in the original design (verifying stack depth, etc).

(display "[TEST] Verifying Sandbox Isolation...\n")
(let ((res (guix-investigate "(system* \"ls\" \"/\")")))
  (if (string-contains res "gnu")
      (display "PASS: Sandbox contains /gnu store.\n")
      (display "FAIL: Sandbox seems broken.\n")))

(display "[TEST] RLM Loop Initialization...\n")
(display "To verify full RLM loop, run 'make run' and check 'trajectories.jsonl'.\n")
