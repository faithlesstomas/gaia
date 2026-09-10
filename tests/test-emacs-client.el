;;; test-emacs-client.el --- GAIA Emacs client protocol tests -*- lexical-binding: t; -*-

(add-to-list 'load-path
             (expand-file-name "../src/gaia-desktop/emacs"
                               (file-name-directory (or load-file-name buffer-file-name))))

(require 'ert)
(require 'cl-lib)
(require 'gaia)

(ert-deftest gaia-chat-maps-gcas-inspection-commands ()
  (should (equal (gaia-chat--input-message "/cognitive-events")
                 '(get-cognitive-events)))
  (should (equal (gaia-chat--input-message "/cognitive-state")
                 '(get-cognitive-state)))
  (should (equal (gaia-chat--input-message "/cognitive-objects")
                 '(get-cognitive-state))))

(ert-deftest gaia-chat-routes-normal-input-through-gcas-conversation ()
  (should (equal (gaia-chat--input-message "Cześć, pamiętasz mnie?")
                 '(converse "Cześć, pamiętasz mnie?")))
  (should (equal (gaia-chat--input-message "/chat hello")
                 '(converse "hello")))
  (should (equal (gaia-chat--input-message "/solve calculate 2+2")
                 '(solve "calculate 2+2"))))

(ert-deftest gaia-chat-validates-resumable-session-identifiers ()
  (should (gaia-chat--valid-session-id-p "gaia-chat_42.1"))
  (should-not (gaia-chat--valid-session-id-p "../escape"))
  (should-not (gaia-chat--valid-session-id-p "contains space")))

(ert-deftest gaia-chat-registers-cognitive-state-renderer ()
  (should (eq (cdr (assq 'cognitive-state gaia-connection-handlers))
              #'gaia-chat--on-cognitive-state)))

(ert-deftest gaia-chat-registers-model-info-handler ()
  (should (eq (cdr (assq 'model-info gaia-connection-handlers))
              #'gaia-chat--on-model-info)))

(ert-deftest gaia-chat-set-model-updates-server-and-mode-line-state ()
  (let (sent)
    (with-temp-buffer
      (setq major-mode 'gaia-mode)
      (cl-letf (((symbol-function 'gaia-chat--send-config-cmd)
                 (lambda (command) (setq sent command))))
        (gaia-chat-set-model " qwen3:4b ")
        (should (equal sent '(set-model "qwen3:4b")))
        (should (equal gaia-chat--model "qwen3:4b"))
        (should-error (gaia-chat-set-model "   ") :type 'user-error)))))

(ert-deftest gaia-chat-model-shortcut-opens-model-selector ()
  (should (eq (lookup-key gaia-chat-mode-map (kbd "C-c C-m"))
              #'gaia-chat-switch-model)))

(ert-deftest gaia-chat-supports-thinking-levels-and-boolean-aliases ()
  (let (sent)
    (with-temp-buffer
      (setq major-mode 'gaia-mode)
      (cl-letf (((symbol-function 'gaia-chat--send-config-cmd)
                 (lambda (command) (setq sent command))))
        (dolist (state '("off" "on" "false" "true" "low" "medium" "high" "max"))
          (gaia-chat-set-thinking state)
          (should (equal sent `(set-thinking ,state))))
        (should-error (gaia-chat-set-thinking "turbo"))))))

(ert-deftest gaia-chat-toggle-disables-an-active-thinking-level ()
  (let (sent)
    (with-temp-buffer
      (setq major-mode 'gaia-mode)
      (cl-letf (((symbol-function 'gaia-chat--ensure-connected) #'ignore)
                ((symbol-function 'gaia-send)
                 (lambda (_command) (setq gaia-chat--pending-thinking "high")))
                ((symbol-function 'gaia-chat--send-config-cmd)
                 (lambda (command) (setq sent command))))
        (gaia-chat-toggle-thinking)
        (should (equal sent '(set-thinking "off")))))))

(ert-deftest gaia-chat-toggle-restores-the-last-thinking-level ()
  (let (sent)
    (with-temp-buffer
      (setq major-mode 'gaia-mode)
      (setq-local gaia-chat--last-enabled-thinking "medium")
      (cl-letf (((symbol-function 'gaia-chat--ensure-connected) #'ignore)
                ((symbol-function 'gaia-send)
                 (lambda (_command) (gaia-chat--on-thinking-info "off")))
                ((symbol-function 'gaia-chat--send-config-cmd)
                 (lambda (command) (setq sent command))))
        (gaia-chat-toggle-thinking)
        (should (equal sent '(set-thinking "medium")))
        (should (equal gaia-chat--thinking-mode "medium"))
        (should (equal gaia-chat--last-enabled-thinking "medium"))))))

(ert-deftest gaia-chat-mode-line-shows-session-model-thinking-and-status ()
  (with-temp-buffer
    (setq-local gaia-chat--session-id "session-42")
    (setq-local gaia-chat--model "qwen3:4b")
    (setq-local gaia-chat--thinking-mode "high")
    (cl-letf (((symbol-function 'gaia-connected-p) (lambda () t)))
      (let ((info (gaia-chat--mode-line-info)))
        (should (string-match-p "session:session-42" info))
        (should (string-match-p "model:qwen3:4b" info))
        (should (string-match-p "think:high" info))
        (should (string-match-p "ready" info))))))

(ert-deftest gaia-chat-mode-line-hides-thinking-for-unsupported-models ()
  (with-temp-buffer
    (setq-local gaia-chat--model "llama3:8b")
    (setq-local gaia-chat--thinking-mode "high")
    (cl-letf (((symbol-function 'gaia-connected-p) (lambda () nil)))
      (let ((info (gaia-chat--mode-line-info)))
        (should (string-match-p "model:llama3:8b" info))
        (should-not (string-match-p "think:" info))
        (should (string-match-p "offline" info))))))

(ert-run-tests-batch-and-exit)

;;; test-emacs-client.el ends here
