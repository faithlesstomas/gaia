(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (gaia core)
             (srfi srfi-64)
             (ice-9 threads))

(test-begin "gaia-interrupts")

;; --- check-interrupt! ---

(test-group "check-interrupt!"
  (test-assert "does nothing when flag is false"
    (begin
      (module-set! (resolve-module '(gaia core)) '*interrupted* #f)
      (check-interrupt!)
      #t))

  (test-error "throws user-interrupt when flag is true"
    'user-interrupt
    (begin
      (module-set! (resolve-module '(gaia core)) '*interrupted* #t)
      (check-interrupt!)))

  (test-equal "resets flag after throwing"
    #f
    (begin
      (module-set! (resolve-module '(gaia core)) '*interrupted* #t)
      (catch 'user-interrupt
        (lambda () (check-interrupt!))
        (lambda _ #t))
      (module-ref (resolve-module '(gaia core)) '*interrupted*))))

(test-end "gaia-interrupts")
