(define-module (gaia actors)
  #:use-module (gaia sandbox-actor)
  #:use-module (gaia agent-actor)
  #:use-module (gaia session-orchestrator)
  #:re-export (^repl-sandbox
               ^repl-sandbox-from-env
               ^llm-client
               ^agent-actor
               ^session-orchestrator
               current-<-np-extern))

;; Re-export or define wrappers for private functions accessed in tests
(define (clean-history history)
  ((@@ (gaia session-orchestrator) clean-history) history))

(define (replay-history env history)
  ((@@ (gaia sandbox-actor) replay-history) env history))
