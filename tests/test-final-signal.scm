(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (gaia core)
             (srfi srfi-64))

(test-begin "final-signal")

(test-group "extract-final-signal"
  ;; Test FINAL(answer) extraction
  (test-equal "Extract FINAL with simple answer"
    '(final "42")
    (extract-final-signal "The answer is FINAL(42)"))
  
  (test-equal "Extract FINAL with sentence"
    '(final "The file contains 5 errors")
    (extract-final-signal "Analysis complete. FINAL(The file contains 5 errors)"))
  
  ;; Test FINAL_VAR(variable) extraction
  (test-equal "Extract FINAL_VAR"
    '(final-var "result")
    (extract-final-signal "Calculation done. FINAL_VAR(result)"))
  
  (test-equal "Extract FINAL_VAR with underscores"
    '(final-var "error_count")
    (extract-final-signal "FINAL_VAR(error_count)"))
  
  ;; Test no signal
  (test-equal "No FINAL signal"
    #f
    (extract-final-signal "Still thinking... need more steps"))
  
  (test-equal "Partial FINAL (invalid)"
    #f
    (extract-final-signal "FINAL but no parentheses")))

(test-group "extract-confidence"
  ;; Test valid confidence scores
  (test-equal "Extract confidence 95"
    95
    (extract-confidence "I am done. CONFIDENCE(95)"))
  
  (test-equal "Extract confidence 100"
    100
    (extract-confidence "Task complete! CONFIDENCE(100)"))
  
  (test-equal "Extract confidence 0"
    0
    (extract-confidence "Not sure at all. CONFIDENCE(0)"))
  
  (test-equal "Extract confidence 50"
    50
    (extract-confidence "Halfway there. CONFIDENCE(50)"))
  
  ;; Test invalid scores (out of range)
  (test-equal "Confidence >100 invalid"
    #f
    (extract-confidence "CONFIDENCE(150)"))
  
  (test-equal "Negative confidence invalid"
    #f
    (extract-confidence "CONFIDENCE(-10)"))
  
  ;; Test no confidence
  (test-equal "No confidence signal"
    #f
    (extract-confidence "Just thinking...")))

(test-group "combined-signals"
  ;; Test both FINAL and CONFIDENCE in same response
  (test-equal "Extract FINAL when both present"
    '(final "Done")
    (extract-final-signal "FINAL(Done) CONFIDENCE(100)"))
  
  (test-equal "Extract CONFIDENCE when both present"
    100
    (extract-confidence "FINAL(Done) CONFIDENCE(100)")))

(test-group "clean-assistant-content"
  (test-equal "No formatting cleaning"
    "Hello world"
    (clean-assistant-content "Hello world"))

  (test-equal "Strip confidence tags"
    "Hello"
    (clean-assistant-content "Hello <confidence>95</confidence>"))

  (test-equal "Strip think tags"
    "Hello"
    (clean-assistant-content "<think>thinking</think>Hello"))

  (test-equal "Strip |think| tags"
    "Hello"
    (clean-assistant-content "Hello<|think|>thinking</|think|>"))

  (test-equal "Strip code blocks"
    "Hello"
    (clean-assistant-content "Hello\n```repl\n(display 42)\n```"))

  (test-equal "Strip FINAL and CONFIDENCE macros"
    "Hello"
    (clean-assistant-content "Hello FINAL(42) CONFIDENCE(90)"))

  (test-equal "Strip multiline mix"
    "Real answer here"
    (clean-assistant-content "<think>\nThinking hard\n</think>\nReal answer here\n```repl\n(write-file \"a.txt\" \"content\")\n```\nCONFIDENCE(98)\nFINAL(answer)")))

(test-end "final-signal")

