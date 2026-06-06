(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (srfi srfi-64)
             (goblins)
             (fibers)
             (gaia actors))

(test-begin "gaia-actors")

;; Mock chat-with-llm to simulate blocking Fibers I/O
(define (chat-with-llm session-id input model system-prompt . args)
  (display "[MOCK] chat-with-llm called!\n")
  ;; Sleep using Fibers to simulate socket read delay
  (sleep 0.1)
  (display "[MOCK] chat-with-llm sleep finished!\n")
  `(("payload" . (("content" . "Hello! I am a mocked response.")
                  ("reasoning" . "Thinking...")))))

;; Define the test binding for chat-with-llm in gaia llm-client so actors.scm sees it
(let ((mod (resolve-module '(gaia llm-client) #:ensure #f)))
  (when mod
    (module-set! mod 'chat-with-llm chat-with-llm)
    (display "[MOCK] Redefined chat-with-llm in (gaia llm-client)\n")))

(test-assert "llm-client actor chat method does not crash under continuation barrier"
  (let* ((session-vat (spawn-vat))
         (done? #f)
         (result #f))
    (run-fibers
     (lambda ()
       ;; Clear Goblins parameters for the current fiber (since run-fibers might inherit them,
       ;; or we want to simulate the environment of the actor-spawned fiber)
       (let ((llm-client (with-vat session-vat (spawn ^llm-client session-vat))))
         (with-vat session-vat
           (let ((p (<- llm-client 'chat "session-1" "hello" "gemma" "sys" #f '() (lambda (evt) #t))))
             (on p
                 (lambda (res)
                   (display "[TEST] Promise resolved with: ")
                   (write res)
                   (newline)
                   (set! result res)
                   (set! done? #t))
                 #:catch
                 (lambda (err)
                   (display "[TEST] Promise caught error: ")
                   (write err)
                   (newline)))))
         ;; Loop to keep the main fiber alive until the promise resolves
         (let loop ()
           (unless done?
             (sleep 0.01)
             (loop)))))
     #:drain? #t)
    (display (format #f "[TEST] done?: ~s, result: ~s\n" done? result))
    (and done?
         (list? result)
         (equal? (assoc-ref (assoc-ref result "payload") "content")
                 "Hello! I am a mocked response."))))

(test-end "gaia-actors")
