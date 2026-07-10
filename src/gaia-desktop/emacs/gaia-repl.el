;;; gaia-repl.el --- Interactive REPL Buffer for GAIA -*- lexical-binding: t; -*-

;; Author: Tomasz
;; Keywords: comm, processes, scheme

;;; Commentary:
;; Interactive session REPL for GAIA, derived from comint-mode.
;; Routes input to the associated chat buffer's connection.

;;; Code:

(require 'comint)
(require 'gaia-connection)

(defgroup gaia-repl nil
  "Interactive REPL for GAIA."
  :group 'gaia
  :prefix "gaia-repl-")

(defvar-local gaia-repl--session-id nil
  "Active session ID in the REPL buffer.")

(defvar-local gaia-repl--chat-buffer nil
  "The chat buffer associated with this REPL buffer.")

(define-derived-mode gaia-repl-mode comint-mode "GAIA REPL"
  "Major mode for GAIA session REPL."
  (setq comint-input-sender #'gaia-repl--send-input)
  (setq-local comint-prompt-regexp "^gaia-repl > ")
  (setq-local comint-process-echoes nil))

(defun gaia-repl--send-input (_proc input)
  "Send user input to the GAIA REPL server."
  (let ((clean-input (substring-no-properties (string-trim input))))
    (unless (string-empty-p clean-input)
      (if (and gaia-repl--chat-buffer (buffer-live-p gaia-repl--chat-buffer))
          (let ((assistant-active (with-current-buffer gaia-repl--chat-buffer gaia-chat--active-request)))
            (if assistant-active
                (let ((inhibit-read-only t)
                      (dummy-proc (get-buffer-process (current-buffer))))
                  (goto-char (point-max))
                  (insert "\nERROR: REPL is locked while the Assistant is running a task. Please wait.\n\n")
                  (insert "gaia-repl > ")
                  (when dummy-proc
                    (set-marker (process-mark dummy-proc) (point))))
              (with-current-buffer gaia-repl--chat-buffer
                ;; Send (repl input) to GAIA
                (gaia-send `(repl ,clean-input)))))
        (error "Associated chat buffer is not available")))))

(defun gaia-repl--initialize-process ()
  "Start a dummy cat process for comint."
  (unless (get-buffer-process (current-buffer))
    (let ((proc (start-process "gaia-repl-dummy" (current-buffer) "cat")))
      (set-process-query-on-exit-flag proc nil)
      (set-process-filter proc (lambda (_proc _string) nil)))))

(defun gaia-repl--initialize-buffer ()
  "Set up the REPL buffer."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert ";;; GAIA Interactive REPL Session: " (or gaia-repl--session-id "") "\n")
    (insert ";;; Type Scheme expressions to explore or modify the state.\n\n")
    (gaia-repl--initialize-process)
    ;; Set prompt
    (goto-char (point-max))
    (insert "gaia-repl > ")
    (set-marker (process-mark (get-buffer-process (current-buffer))) (point))))

;;;###autoload
(defun gaia-repl ()
  "Open the GAIA REPL buffer for the active session."
  (interactive)
  (let* ((chat-buf (or (and (eq major-mode 'gaia-mode) (current-buffer))
                       (get-buffer "*gaia*")
                       (cl-find-if (lambda (b) (with-current-buffer b (eq major-mode 'gaia-mode))) (buffer-list))))
         (session-id (if chat-buf
                         (with-current-buffer chat-buf gaia-chat--session-id)
                       (format "emacs-%d" (time-convert nil 'integer))))
         (buf-name (format "*gaia-repl-%s*" session-id))
         (buf (get-buffer-create buf-name)))
    (with-current-buffer buf
      (unless (eq major-mode 'gaia-repl-mode)
        (gaia-repl-mode)
        (setq-local gaia-repl--session-id session-id)
        (setq-local gaia-repl--chat-buffer chat-buf)
        (gaia-repl--initialize-buffer))
      ;; Link back in the chat buffer
      (when chat-buf
        (with-current-buffer chat-buf
          (setq-local gaia-chat--repl-buffer buf))))
    (pop-to-buffer buf)))

(defun gaia-repl--on-result (result)
  "Insert the REPL result into the active REPL buffer."
  (let ((inhibit-read-only t)
        (proc (get-buffer-process (current-buffer))))
    (goto-char (point-max))
    (insert result "\n\n")
    (insert "gaia-repl > ")
    (when proc
      (set-marker (process-mark proc) (point)))))

(defun gaia-repl--on-error (err)
  "Insert the REPL error into the active REPL buffer."
  (let ((inhibit-read-only t)
        (proc (get-buffer-process (current-buffer))))
    (goto-char (point-max))
    (insert "ERROR: " err "\n\n")
    (insert "gaia-repl > ")
    (when proc
      (set-marker (process-mark proc) (point)))))

(provide 'gaia-repl)
;;; gaia-repl.el ends here
