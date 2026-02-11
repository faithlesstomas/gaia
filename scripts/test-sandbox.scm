(use-modules (gaia sandbox)
             (srfi srfi-64)
             (ice-9 match))

(test-begin "sandbox-security")

;; 1. Test Safe Arithmetic
(test-equal "safe-arithmetic"
  42
  (eval-safe '(+ 40 2)))

;; 2. Test Safe List Operations
(test-equal "safe-list-ops"
  '(1 2 3)
  (eval-safe '(cons 1 (list 2 3))))

;; 3. Test Banned Primitive (system)
(test-error "banned-system-call"
  #t
  (catch #t
         (lambda () (eval-safe '(system "ls")))
         (lambda (key . args) (throw 'error))))

;; 4. Test Banned Primitive (delete-file)
(test-error "banned-delete-file"
  #t
  (catch #t
         (lambda () (eval-safe '(delete-file "test.txt")))
         (lambda (key . args) (throw 'error))))

;; 5. Test Define/Variables
(test-equal "safe-define"
  10
  (eval-safe '(begin (define x 10) x)))

(test-end "sandbox-security")
