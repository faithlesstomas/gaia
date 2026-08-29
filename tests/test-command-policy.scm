(define-module (tests test-command-policy)
  #:use-module (srfi srfi-64)
  #:use-module (gaia sandbox))

(test-begin "gaia-command-policy")

(test-equal "quoted arguments are parsed without shell evaluation"
  '("printf" "a b")
  (parse-command-argv "printf 'a b'"))

(test-assert "shell operators and expansion fail closed"
  (and (not (parse-command-argv "git status; touch /tmp/x"))
       (not (parse-command-argv "git status $(touch /tmp/x)"))
       (not (parse-command-argv "grep x file | head"))
       (not (parse-command-argv "git 'unterminated"))))

(test-assert "safe policy is evaluated on argv and exact git subcommands"
  (and (command-argv-safe? '("git" "status"))
       (command-argv-safe? '("grep" "needle" "file"))
       (not (command-argv-safe? '("git" "push")))
       (not (command-argv-safe? '("git-status")))))

(test-end "gaia-command-policy")
