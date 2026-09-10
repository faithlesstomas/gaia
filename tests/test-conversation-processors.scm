(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (srfi srfi-1)
             (srfi srfi-64)
             (gaia com)
             (gaia cognitive-bus)
             (gaia cognitive-memory)
             (gaia cognitive-process)
             (gaia cognitive-session)
             (gaia cognitive-state)
             (gaia conversation-processors))

(test-begin "gaia-conversation-processors")

(define memory-path "/tmp/gaia-gcas-conversation-memory.scm")
(define state-path "/tmp/gaia-gcas-conversation-state.scm")

(for-each (lambda (path)
            (when (file-exists? path) (delete-file path)))
          (list memory-path state-path))

(define (event-types session)
  (map event-type (state-events (session-state session))))

(define (conversation-speaker co)
  (assoc-ref (co-relations co) 'conversation-speaker))

(define first-prompt #f)
(define first-finished '())
(define first-session
  (make-cognitive-session #:memory-path memory-path #:state-path state-path))

(start-conversation-process!
 first-session "Mam na imię Tomasz."
 #:generate
 (lambda (prompt succeed fail)
   (set! first-prompt prompt)
   (succeed "Miło Cię poznać, Tomaszu."))
 #:on-finished
 (lambda (outcome final-text hypothesis-text)
   (set! first-finished
         (cons (list outcome final-text hypothesis-text) first-finished))))

(test-assert "ordinary conversation completes once through GCAS"
  (and (= (length first-finished) 1)
       (eq? (caar first-finished) 'COMPLETED)
       (string=? (cadar first-finished) "Miło Cię poznać, Tomaszu.")
       (every (lambda (type) (memq type (event-types first-session)))
              '(ConversationTurnReceived MemoryRetrieved HypothesisProposed
                ResponseDeliveryVerified GoalVerificationCompleted
                AnswerRequested GoalVerified GoalCompleted))))

(test-assert "assistant prose remains an unverified hypothesis"
  (let ((responses
         (filter (lambda (co)
                   (eq? (conversation-speaker co) 'ASSISTANT))
                 (memory-objects (session-memory first-session)))))
    (and (= (length responses) 1)
         (eq? (co-type (car responses)) 'hypothesis)
         (eq? (co-provenance (car responses)) 'LLM)
         (eq? (co-epistemic-status (car responses)) 'HYPOTHESIS)
         (eq? (co-verification-status (car responses)) 'UNVERIFIED)
         (assoc-ref (co-relations (car responses)) 'delivery-verified-by))))

(test-assert "delivery Claim verifies scope, not response content"
  (let ((claims
         (filter (lambda (co)
                   (and (fact? co)
                        (eq? (assoc-ref (co-relations co) 'verification-scope)
                             'DELIVERY_ONLY)))
                 (state-objects (session-state first-session)))))
    (and (= (length claims) 1)
         (string-contains (co-content (car claims))
                          "no factual proposition"))))

(define second-prompt #f)
(define second-finished '())
(define restored-session
  (make-cognitive-session #:memory-path memory-path #:state-path state-path))

(start-conversation-process!
 restored-session "Jak mam na imię?"
 #:generate
 (lambda (prompt succeed fail)
   (set! second-prompt prompt)
   (succeed "Powiedziałeś, że masz na imię Tomasz."))
 #:on-finished
 (lambda (outcome final-text hypothesis-text)
   (set! second-finished
         (cons (list outcome final-text hypothesis-text) second-finished))))

(test-assert "fresh session reconstructs relevant dialogue without transcript replay"
  (and (= (length second-finished) 1)
       (eq? (caar second-finished) 'COMPLETED)
       (string-contains second-prompt
                        "GCAS conversational projection (not a transcript replay)")
       (string-contains second-prompt "Tomasz")
       (string-contains second-prompt "Miło Cię poznać")
       (= (length (memory-conversation-turns
                   (session-memory restored-session) #:limit 20))
          4)))

(test-assert "profile retrieval question is episodic, not fresh user testimony"
  (let ((question
         (find (lambda (co)
                 (and (eq? (conversation-speaker co) 'USER)
                      (string=? (co-content co) "Jak mam na imię?")))
               (memory-objects (session-memory restored-session)))))
    (and question (eq? (memory-role question) 'EPISODIC))))

;; Grow durable episodic memory deliberately; prompt projection must remain
;; bounded even though the memory store and UI transcript can continue growing.
(do ((index 0 (+ index 1)))
    ((= index 20))
  (memory-record-conversation-turn!
   (session-memory restored-session)
   (if (even? index) 'USER 'ASSISTANT)
   (string-append "Długi historyczny wpis numer " (number->string index) ": "
                  (make-string 180 #\x))))

(define bounded-prompt #f)
(start-conversation-process!
 restored-session "Porozmawiajmy teraz o czymś nowym."
 #:recent-limit 3
 #:relevant-limit 2
 #:max-context-chars 700
 #:generate
 (lambda (prompt succeed fail)
   (set! bounded-prompt prompt)
   (succeed "Jasne, o czym chcesz porozmawiać?")))

(test-assert "conversation projection stays bounded as durable memory grows"
  (and (string? bounded-prompt)
       (<= (string-length bounded-prompt) 700)
       (string-contains bounded-prompt "Current user utterance")))

(define empty-finished '())
(define turns-before-empty
  (length (memory-conversation-turns
           (session-memory restored-session) #:limit 100)))
(start-conversation-process!
 restored-session "Czy jesteś?"
 #:generate (lambda (prompt succeed fail) (succeed "   "))
 #:on-finished
 (lambda (outcome final-text hypothesis-text)
   (set! empty-finished (cons outcome empty-finished))))

(test-assert "empty generation terminates once without storing assistant prose"
  (and (equal? empty-finished '(INSUFFICIENT_INFORMATION))
       (= (+ turns-before-empty 1)
          (length (memory-conversation-turns
                   (session-memory restored-session) #:limit 100)))))

(define late-success #f)
(define interrupt-finished '())
(start-conversation-process!
 restored-session "Poczekaj na odpowiedź."
 #:generate
 (lambda (prompt succeed fail)
   (set! late-success succeed))
 #:on-finished
 (lambda (outcome final-text hypothesis-text)
   (set! interrupt-finished (cons outcome interrupt-finished))))
(session-request-interrupt! restored-session)
(late-success "Ta odpowiedź przyszła za późno.")

(test-assert "interrupt wins exactly once and late model output is ignored"
  (and (equal? interrupt-finished '(USER_INTERRUPTED))
       (not (any (lambda (co)
                   (and (eq? (conversation-speaker co) 'ASSISTANT)
                        (string=? (co-content co)
                                  "Ta odpowiedź przyszła za późno.")))
                 (memory-objects (session-memory restored-session))))))

(for-each (lambda (path)
            (when (file-exists? path) (delete-file path)))
          (list memory-path state-path))

(test-end "gaia-conversation-processors")
