;;; gaia-hitl.el --- Human-in-the-Loop Permission Prompt for GAIA -*- lexical-binding: t; -*-

;; Author: Tomasz
;; Keywords: comm, processes, tools

;;; Commentary:
;; Handles permission requests from the GAIA server (e.g. file writes, commands),
;; renders diffs or code syntax highlighted popups, and prompts the user.

;;; Code:

(require 'diff-mode)
(require 'gaia-connection)

(defgroup gaia-hitl nil
  "Human-in-the-Loop settings for GAIA."
  :group 'gaia
  :prefix "gaia-hitl-")

(defvar gaia-hitl--active-request nil
  "The current active permission request expression.")

(defun gaia-hitl--on-request (expr)
  "Callback for incoming permission-request event."
  (setq gaia-hitl--active-request expr)
  (let ((handled nil))
    (when (listp expr)
      (cond
       ;; Handle write-file
       ((eq (car expr) 'write-file)
        (let ((path (cadr expr))
              (content (caddr expr)))
          (gaia-hitl--handle-write-file path content)
          (setq handled t)))
       (t nil)))
    ;; Handle general command/eval expressions
    (unless handled
      (gaia-hitl--handle-generic expr))))

(defun gaia-hitl--handle-write-file (path content)
  "Display diff for proposed write to PATH and prompt."
  (let* ((buf-name "*gaia-permission*")
         (buf (get-buffer-create buf-name))
         (file-exists (file-exists-p path)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (if (not file-exists)
            (progn
              (insert "Proposed NEW file: " path "\n\n")
              (insert content))
          (let ((temp-file (make-temp-file "gaia-proposed-")))
            (with-temp-file temp-file
              (insert content))
            ;; Generate diff
            (insert "Proposed EDIT to: " path "\n\n")
            (let ((exit-code (call-process "diff" nil t nil "-u" path temp-file)))
              (delete-file temp-file)
              (when (eq exit-code 0)
                (insert "No differences (file is identical to proposed content).\n")))))
        (diff-mode)
        (set-buffer-modified-p nil)
        (setq buffer-read-only t)))
    ;; Display buffer
    (display-buffer buf)
    (gaia-hitl--prompt-user (format "Write file %s?" (file-name-nondirectory path)))))

(defun gaia-hitl--handle-generic (expr)
  "Display generic expression to be executed and prompt."
  (let* ((buf-name "*gaia-permission*")
         (buf (get-buffer-create buf-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Proposed Code Execution:\n\n")
        (let ((formatted (format "%S" expr)))
          (insert (replace-regexp-in-string "\\bnil\\b" "#f" formatted)))
        (scheme-mode)
        (set-buffer-modified-p nil)
        (setq buffer-read-only t)))
    (display-buffer buf)
    (gaia-hitl--prompt-user "Execute Scheme expression?")))

(defun gaia-hitl--prompt-user (action-prompt)
  "Prompt the user for permission response."
  (let ((approved nil)
        (response-val nil))
    (save-window-excursion
      (let ((char (read-char (concat action-prompt " [y]es / [n]o / [a]lways exact / [d]irectory path: "))))
        (cond
         ((memq char '(?y ?Y))
          (setq approved t)
          (setq response-val t))
         ((memq char '(?n ?N ?\C-g))
          (setq approved t)
          (setq response-val nil))
         ((memq char '(?a ?A))
          (setq approved t)
          ;; Send (always <expr>)
          (setq response-val `(always ,gaia-hitl--active-request)))
         ((memq char '(?d ?D))
          (when (and (listp gaia-hitl--active-request) (eq (car gaia-hitl--active-request) 'write-file))
            (let* ((path (cadr gaia-hitl--active-request))
                   (dir (file-name-directory (expand-file-name path))))
              (setq approved t)
              ;; Send (directory <dir>)
              (setq response-val `(directory ,dir)))))
         (t
          (message "Invalid choice. Denying permission.")
          (setq approved t)
          (setq response-val nil)))))
    ;; Clean up buffer window
    (let ((buf (get-buffer "*gaia-permission*")))
      (when buf
        (kill-buffer buf)))
    (when approved
      (gaia-send `(permission-response ,response-val)))))

;; Register request handler
(gaia-connection-register-handler 'permission-request #'gaia-hitl--on-request)

(provide 'gaia-hitl)
;;; gaia-hitl.el ends here
