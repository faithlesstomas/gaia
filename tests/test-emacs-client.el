;;; test-emacs-client.el --- GAIA Emacs client protocol tests -*- lexical-binding: t; -*-

(add-to-list 'load-path
             (expand-file-name "../src/gaia-desktop/emacs"
                               (file-name-directory (or load-file-name buffer-file-name))))

(require 'ert)
(require 'gaia)

(ert-deftest gaia-chat-maps-gcas-inspection-commands ()
  (should (equal (gaia-chat--input-message "/cognitive-events")
                 '(get-cognitive-events)))
  (should (equal (gaia-chat--input-message "/cognitive-state")
                 '(get-cognitive-state)))
  (should (equal (gaia-chat--input-message "/cognitive-objects")
                 '(get-cognitive-state))))

(ert-deftest gaia-chat-registers-cognitive-state-renderer ()
  (should (eq (cdr (assq 'cognitive-state gaia-connection-handlers))
              #'gaia-chat--on-cognitive-state)))

(ert-run-tests-batch-and-exit)

;;; test-emacs-client.el ends here
