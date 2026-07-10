;;; gaia-chat.el --- Interactive Org-Mode Chat Interface for GAIA -*- lexical-binding: t; -*-

;; Author: Tomasz
;; Keywords: comm, processes, hypermedia

;;; Commentary:
;; Provides a derived org-mode buffer for interacting with the GAIA agent.
;; Handles streaming tokens, folding thoughts, rendering errors, and sending prompts.

;;; Code:

(require 'org)
(require 'gaia-connection)

(defgroup gaia-chat nil
  "Interactive chat buffer for GAIA."
  :group 'gaia
  :prefix "gaia-chat-")

(defcustom gaia-chat-buffer-name "*gaia*"
  "Name of the interactive GAIA buffer."
  :type 'string
  :group 'gaia-chat)

(defvar-local gaia-chat--stream-state nil
  "Current streaming state: nil, \\='token, \\='thought.")

(defvar-local gaia-chat--session-id nil
  "Active session ID in the buffer.")

(defvar gaia-chat-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'gaia-chat-send)
    (define-key map (kbd "C-c C-k") #'gaia-chat-interrupt)
    (define-key map (kbd "C-c C-l") #'gaia-chat-clear)
    (define-key map (kbd "C-c C-s") #'gaia-chat-switch-session)
    (define-key map (kbd "C-c C-m") #'gaia-chat-switch-model)
    (define-key map (kbd "C-c C-t") #'gaia-chat-toggle-thinking)
    (define-key map (kbd "C-c C-h") #'gaia-chat-show-history)
    map)
  "Keymap for `gaia-mode'.")

(define-derived-mode gaia-mode org-mode "GAIA Chat"
  "Major mode for GAIA interactive buffers, derived from Org-mode."
  (setq-local gaia-chat--stream-state nil)
  (setq-local gaia-chat--session-id (format "emacs-%d" (time-convert nil 'integer)))
  ;; Enable word wrapping and prevent truncation (even in split/partial-width windows)
  (setq-local truncate-lines nil)
  (setq-local word-wrap t)
  (setq-local truncate-partial-width-windows nil)
  (setq-local org-startup-truncated nil)
  (visual-line-mode 1)
  ;; Smooth scrolling during streaming (prevents buffer jumping)
  (setq-local scroll-conservatively 10000)
  ;; Setup custom local variables or hooks if needed
  (use-local-map gaia-chat-mode-map))

(defun gaia-chat-buffer ()
  "Get or create the GAIA buffer."
  (let ((buf (get-buffer-create gaia-chat-buffer-name)))
    (with-current-buffer buf
      (unless (eq major-mode 'gaia-mode)
        (gaia-mode)
        (gaia-chat--initialize-buffer)))
    buf))

(defun gaia-chat--initialize-buffer ()
  "Set up the initial contents of the GAIA buffer."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert "* GAIA Agent Session\n")
    (insert "Welcome to GNU AI Assistant (GAIA) in Emacs.\n")
    (insert "Type your task after the prompt below and press `C-c C-c` to send.\n\n")
    (gaia-chat--insert-prompt)))

(defun gaia-chat--insert-prompt ()
  "Insert the input prompt at the end of the buffer."
  (let ((inhibit-read-only t))
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (insert "\nGAIA > ")
    ;; Ensure prompt is not read-only but user cannot delete the text of prompt
    (let ((prompt-start (- (point) 7)))
      (add-text-properties prompt-start (point)
                           '(read-only t rear-nonsticky t face bold)))))

(defun gaia-chat-send ()
  "Send the text written after the prompt to the GAIA server."
  (interactive)
  (let* ((buf (gaia-chat-buffer))
         (prompt-pos (with-current-buffer buf
                       (save-excursion
                         (goto-char (point-max))
                         (search-backward "GAIA > " nil t)))))
    (if (not prompt-pos)
        (error "Prompt not found in GAIA buffer")
      (let* ((input-start (+ prompt-pos 7))
             (input (with-current-buffer buf
                      (string-trim (buffer-substring-no-properties input-start (point-max))))))
        (if (string-empty-p input)
            (message "Input is empty")
          (with-current-buffer buf
            (let ((inhibit-read-only t))
              ;; Remove the prompt and raw input and format as Org User Heading
              (delete-region prompt-pos (point-max))
              (goto-char (point-max))
              (insert (format "** User [%s]\n" (format-time-string "%Y-%m-%d %H:%M:%S")))
              (insert input "\n\n")
              ;; Start connection if not active
              (unless (gaia-connected-p)
                (gaia-connect)
                ;; Send session command immediately
                (gaia-send `(session ,gaia-chat--session-id))
                ;; Accept output to let socket process the queue
                (accept-process-output gaia-connection-process 0.1))
              ;; Send command
              (gaia-send `(eval ,input))
              (setq gaia-chat--stream-state nil)
              (message "Prompt sent to GAIA..."))))))))

(defun gaia-chat-interrupt ()
  "Interrupt the active GAIA agent."
  (interactive)
  (when (gaia-connected-p)
    (gaia-send '(interrupt))
    (message "Sent interrupt to GAIA server.")))

(defun gaia-chat-clear ()
  "Clear current environment and history."
  (interactive)
  (when (gaia-connected-p)
    (gaia-send '(clear))
    (message "Cleared GAIA history.")))

(defun gaia-chat-switch-session ()
  "Switch to another session ID."
  (interactive)
  (if (not (gaia-connected-p))
      (message "Please connect first.")
    (gaia-send '(list-sessions))))

(defun gaia-chat-switch-model ()
  "Switch active LLM model."
  (interactive)
  (if (not (gaia-connected-p))
      (message "Please connect first.")
    (gaia-send '(list-models))))

(defun gaia-chat-toggle-thinking ()
  "Toggle thinking mode on the server."
  (interactive)
  (if (not (gaia-connected-p))
      (message "Please connect first.")
    (gaia-send '(get-thinking))))

(defun gaia-chat-show-history ()
  "Get conversation history from server."
  (interactive)
  (if (not (gaia-connected-p))
      (message "Please connect first.")
    (gaia-send '(get-history))))

(defun gaia-chat--scroll-to-bottom ()
  "Scroll windows showing GAIA buffer to the bottom."
  (let ((buf (gaia-chat-buffer)))
    (dolist (win (get-buffer-window-list buf nil t))
      (set-window-point win (point-max)))))

;;; Handler functions for GAIA socket events

(defun gaia-chat--on-token (token)
  "Handle a streamed token."
  (with-current-buffer (gaia-chat-buffer)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (cond
       ;; Transition to token stream
       ((not (eq gaia-chat--stream-state 'token))
        (when (eq gaia-chat--stream-state 'thought)
          (insert "\n#+END_QUOTE\n\n"))
        (insert "*** Response\n")
        (setq gaia-chat--stream-state 'token))
       (t nil))
      (insert token)
      (gaia-chat--scroll-to-bottom))))

(defun gaia-chat--on-thought (thought)
  "Handle a streamed thinking token."
  (with-current-buffer (gaia-chat-buffer)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (cond
       ;; Transition to thought stream
       ((not (eq gaia-chat--stream-state 'thought))
        (when (eq gaia-chat--stream-state 'token)
          (insert "\n"))
        (insert "*** Thinking\n#+BEGIN_QUOTE\n")
        (setq gaia-chat--stream-state 'thought))
       (t nil))
      (insert thought)
      (gaia-chat--scroll-to-bottom))))

(defun gaia-chat--on-status (status)
  "Display status in echo area."
  (message "GAIA Status: %s" status))

(defun gaia-chat--on-code (code)
  "Insert executing code block."
  (with-current-buffer (gaia-chat-buffer)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (when (eq gaia-chat--stream-state 'thought)
        (insert "\n#+END_QUOTE\n\n")
        (setq gaia-chat--stream-state nil))
      (insert "*** Code Execution\n")
      (insert "#+BEGIN_SRC scheme\n" code "\n#+END_SRC\n\n")
      (gaia-chat--scroll-to-bottom))))

(defun gaia-chat--on-result (result)
  "Insert code execution result."
  (with-current-buffer (gaia-chat-buffer)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert "#+RESULTS:\n: " (replace-regexp-in-string "\n" "\n: " result) "\n\n")
      (gaia-chat--scroll-to-bottom))))

(defun gaia-chat--on-repl-error (err)
  "Insert REPL error."
  (with-current-buffer (gaia-chat-buffer)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert "#+RESULTS:\n: ERROR: " (replace-regexp-in-string "\n" "\n: " err) "\n\n")
      (gaia-chat--scroll-to-bottom))))

(defun gaia-chat--on-final (answer)
  "Insert the final response and prepare the next prompt."
  (with-current-buffer (gaia-chat-buffer)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (when (eq gaia-chat--stream-state 'thought)
        (insert "\n#+END_QUOTE\n\n"))
      (insert "*** Final Answer\n" answer "\n")
      (setq gaia-chat--stream-state nil)
      (gaia-chat--insert-prompt)
      (gaia-chat--scroll-to-bottom)
      (pop-to-buffer (current-buffer) '((display-buffer-reuse-window display-buffer-same-window))))))

(defun gaia-chat--on-error (err)
  "Insert server error."
  (with-current-buffer (gaia-chat-buffer)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert "\n*** Server Error\n" err "\n")
      (setq gaia-chat--stream-state nil)
      (gaia-chat--insert-prompt)
      (gaia-chat--scroll-to-bottom)
      (pop-to-buffer (current-buffer) '((display-buffer-reuse-window display-buffer-same-window))))))

;; Register handlers
(gaia-connection-register-handler 'token #'gaia-chat--on-token)
(gaia-connection-register-handler 'thought #'gaia-chat--on-thought)
(gaia-connection-register-handler 'status #'gaia-chat--on-status)
(gaia-connection-register-handler 'code #'gaia-chat--on-code)
(gaia-connection-register-handler 'result #'gaia-chat--on-result)
(gaia-connection-register-handler 'repl-error #'gaia-chat--on-repl-error)
(gaia-connection-register-handler 'final #'gaia-chat--on-final)
(gaia-connection-register-handler 'error #'gaia-chat--on-error)

(provide 'gaia-chat)
;;; gaia-chat.el ends here
