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

(defgroup gaia nil
  "Native Emacs Client for GAIA."
  :group 'external)

;;;###autoload
(defun gaia ()
  "Start or switch to the interactive GAIA agent buffer."
  (interactive)
  (let ((buf (gaia-chat-buffer)))
    (pop-to-buffer buf)))

(provide 'gaia)
;;; gaia.el ends here
