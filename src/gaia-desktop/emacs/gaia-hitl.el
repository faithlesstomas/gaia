;;; gaia-hitl.el --- Human-in-the-Loop Permission Prompt for GAIA -*- lexical-binding: t; -*-

;; Author: Tomasz
;; Keywords: comm, processes, tools

;;; Commentary:
;; Handles permission requests from the GAIA server (e.g. file writes, commands),
;; renders diffs or code syntax highlighted popups in a non-blocking interactive buffer,
;; and handles permission-response dispatching.

;;; Code:

(require 'diff-mode)
(require 'gaia-connection)

(defgroup gaia-hitl nil
  "Human-in-the-Loop settings for GAIA."
  :group 'gaia
  :prefix "gaia-hitl-")

(defvar-local gaia-hitl--request nil
  "The current active permission request expression.")

(defvar-local gaia-hitl--responded nil
  "Whether the current request has been responded to.")

(defvar gaia-hitl-font-lock-keywords
  '(("^\\+.*" . 'diff-added)
    ("^\\-.*" . 'diff-removed)
    ("^@@.*" . 'diff-hunk-header)
    ("^Proposed.*" . 'bold)
    ("^Actions:.*" . 'bold)
    ("^===.*" . 'shadow))
  "Font lock keywords for `gaia-hitl-mode'.")

(defvar gaia-hitl-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "y") #'gaia-hitl-approve)
    (define-key map (kbd "n") #'gaia-hitl-deny)
    (define-key map (kbd "a") #'gaia-hitl-always)
    (define-key map (kbd "d") #'gaia-hitl-directory)
    (define-key map (kbd "C-c C-c") #'gaia-hitl-approve)
    (define-key map (kbd "C-c C-k") #'gaia-hitl-deny)
    map)
  "Keymap for `gaia-hitl-mode'.")

(define-derived-mode gaia-hitl-mode special-mode "GAIA HITL"
  "Major mode for GAIA Human-in-the-Loop permission reviews."
  (setq-local font-lock-defaults '(gaia-hitl-font-lock-keywords)))

(defun gaia-hitl-respond (value)
  "Send VALUE as the permission response and clean up."
  (unless gaia-hitl--responded
    (setq gaia-hitl--responded t)
    (gaia-send `(permission-response ,value))
    (message "Sent permission response: %S" value)
    (let ((buf (current-buffer)))
      (kill-buffer buf))))

(defun gaia-hitl-approve ()
  "Approve the proposed action."
  (interactive)
  (gaia-hitl-respond t))

(defun gaia-hitl-deny ()
  "Deny the proposed action."
  (interactive)
  (gaia-hitl-respond nil))

(defun gaia-hitl-always ()
  "Always approve this exact expression."
  (interactive)
  (gaia-hitl-respond `(always ,gaia-hitl--request)))

(defun gaia-hitl-directory ()
  "Approve all write operations in the directory of the file."
  (interactive)
  (if (and (listp gaia-hitl--request) (eq (car gaia-hitl--request) 'write-file))
      (let* ((path (cadr gaia-hitl--request))
             (dir (file-name-directory (expand-file-name path))))
        (gaia-hitl-respond `(directory ,dir)))
    (error "Directory permission is only applicable to write-file requests")))

(defun gaia-hitl--on-kill-buffer ()
  "Ensure a response is sent if the buffer is killed before responding."
  (when (and (eq major-mode 'gaia-hitl-mode)
             (not gaia-hitl--responded))
    (setq gaia-hitl--responded t)
    (gaia-send '(permission-response nil))
    (message "Permission denied (buffer closed).")))

(defun gaia-hitl--on-request (expr)
  "Callback for incoming permission-request event."
  (let ((handled nil))
    (when (listp expr)
      (cond
       ;; Handle write-file
       ((eq (car expr) 'write-file)
        (let ((path (cadr expr))
              (content (caddr expr)))
          (gaia-hitl--handle-write-file path content expr)
          (setq handled t)))
       (t nil)))
    ;; Handle general command/eval expressions
    (unless handled
      (gaia-hitl--handle-generic expr))))

(defun gaia-hitl--insert-buttons ()
  "Insert interactive response buttons."
  (let ((inhibit-read-only t))
    (insert "Actions: ")
    (insert-button "[y] Approve"
                   'action (lambda (_) (gaia-hitl-approve))
                   'follow-link t)
    (insert "   ")
    (insert-button "[n] Deny"
                   'action (lambda (_) (gaia-hitl-deny))
                   'follow-link t)
    (insert "   ")
    (insert-button "[a] Always Exact"
                   'action (lambda (_) (gaia-hitl-always))
                   'follow-link t)
    (when (and (listp gaia-hitl--request) (eq (car gaia-hitl--request) 'write-file))
      (insert "   ")
      (insert-button "[d] Approve Directory"
                     'action (lambda (_) (gaia-hitl-directory))
                     'follow-link t))
    (insert "\n\n")))

(defun gaia-hitl--display-buffer (buf)
  "Display the HITL buffer BUF and select it."
  (pop-to-buffer buf '((display-buffer-reuse-window display-buffer-below-selected))))

(defun gaia-hitl--handle-write-file (path content expr)
  "Display diff for proposed write to PATH and prompt."
  (let* ((buf-name "*gaia-permission*")
         (buf (get-buffer-create buf-name))
         (file-exists (file-exists-p path)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (gaia-hitl-mode)
        (setq gaia-hitl--request expr)
        (setq gaia-hitl--responded nil)
        (add-hook 'kill-buffer-hook #'gaia-hitl--on-kill-buffer nil t)

        (insert "============================================================\n")
        (insert "GAIA Human-in-the-Loop Permission Request\n")
        (insert "============================================================\n\n")
        (gaia-hitl--insert-buttons)

        (if (not file-exists)
            (progn
              (insert "Proposed NEW file: " path "\n")
              (insert "------------------------------------------------------------\n")
              (insert content))
          (let ((temp-file (make-temp-file "gaia-proposed-")))
            (with-temp-file temp-file
              (insert content))
            (insert "Proposed EDIT to: " path "\n")
            (insert "------------------------------------------------------------\n")
            (let ((exit-code (call-process "diff" nil t nil "-u" path temp-file)))
              (delete-file temp-file)
              (when (eq exit-code 0)
                (insert "No differences (file is identical to proposed content).\n")))))
        (set-buffer-modified-p nil)
        (setq buffer-read-only t)))
    (gaia-hitl--display-buffer buf)))

(defun gaia-hitl--handle-generic (expr)
  "Display generic expression to be executed and prompt."
  (let* ((buf-name "*gaia-permission*")
         (buf (get-buffer-create buf-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (gaia-hitl-mode)
        (setq gaia-hitl--request expr)
        (setq gaia-hitl--responded nil)
        (add-hook 'kill-buffer-hook #'gaia-hitl--on-kill-buffer nil t)

        (insert "============================================================\n")
        (insert "GAIA Human-in-the-Loop Permission Request\n")
        (insert "============================================================\n\n")
        (gaia-hitl--insert-buttons)

        (insert "Proposed Code Execution:\n")
        (insert "------------------------------------------------------------\n")
        (let ((formatted (format "%S" expr)))
          (insert (replace-regexp-in-string "\\bnil\\b" "#f" formatted)))
        (insert "\n")
        (set-buffer-modified-p nil)
        (setq buffer-read-only t)))
    (gaia-hitl--display-buffer buf)))

(defun gaia-hitl--on-connection-close ()
  "Clean up HITL buffer on connection close."
  (let ((buf (get-buffer "*gaia-permission*")))
    (when buf
      (with-current-buffer buf
        (setq gaia-hitl--responded t))
      (kill-buffer buf))))

;; Register request handler and connection close hook
(gaia-connection-register-handler 'permission-request #'gaia-hitl--on-request)
(add-hook 'gaia-connection-on-close-hooks #'gaia-hitl--on-connection-close)

(provide 'gaia-hitl)
;;; gaia-hitl.el ends here
