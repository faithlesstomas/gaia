;;; gaia.el --- Native Emacs Client Package for GAIA -*- lexical-binding: t; -*-

;; Author: Tomasz
;; Version: 1.0.0
;; Package-Requires: ((emacs "25.1") (org "9.0"))
;; Keywords: comm, processes, hypermedia, agents, literate programming

;;; Commentary:
;; Fully featured native Emacs client package for GAIA (GNU AI Assistant).
;; Bridges Emacs with the GAIA local headless agent daemon.
;; Includes:
;; - Persistent socket connection client
;; - Derived org-mode buffer with live event streaming
;; - Human-in-the-loop permission diff reviews
;; - Org-Babel integration for Scheme execution in the agent sandbox

;;; Code:

(require 'gaia-connection)
(require 'gaia-chat)
(require 'gaia-hitl)
(require 'ob-gaia)
(require 'gaia-repl)

(defgroup gaia nil
  "Native Emacs Client for GAIA."
  :group 'external)

(defun gaia-chat--get-active-sessions ()
  "Return a list of session IDs from active gaia-mode buffers."
  (let (sessions)
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (when (eq major-mode 'gaia-mode)
          (push gaia-chat--session-id sessions))))
    sessions))

;;;###autoload
(defun gaia (&optional session-id)
  "Start or switch to the interactive GAIA agent buffer.
If SESSION-ID is provided, switch to that session's buffer."
  (interactive)
  (let* ((active-sessions (gaia-chat--get-active-sessions))
         (sid (or session-id
                  (if (and (eq major-mode 'gaia-mode) gaia-chat--session-id)
                      gaia-chat--session-id
                    (if active-sessions
                        (completing-read "Session ID (leave empty for new): "
                                         active-sessions nil nil nil nil
                                         (format "session-%d" (time-convert nil 'integer)))
                      (format "session-%d" (time-convert nil 'integer))))))
         (buf (gaia-chat-buffer sid)))
    (pop-to-buffer buf)))

(provide 'gaia)
;;; gaia.el ends here
