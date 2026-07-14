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

(defvar-local gaia-chat--stream-state nil
  "Current streaming state: nil, \\='token, \\='thought.")

(defvar-local gaia-chat--session-id nil
  "Active session ID in the buffer.")

(defvar-local gaia-chat--repl-buffer nil
  "The REPL buffer associated with this chat buffer.")

(defvar-local gaia-chat--active-request nil
  "Non-nil if the Assistant is currently running a request.")

(defvar gaia-chat-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'gaia-chat-send)
    (define-key map (kbd "<C-return>") #'gaia-chat-send)
    (define-key map (kbd "C-<return>") #'gaia-chat-send)
    (define-key map (kbd "C-c C-k") #'gaia-chat-interrupt)
    (define-key map (kbd "C-c C-l") #'gaia-chat-clear)
    (define-key map (kbd "C-c C-s") #'gaia-chat-switch-session)
    (define-key map (kbd "C-c C-m") #'gaia-chat-switch-model)
    (define-key map (kbd "C-c C-t") #'gaia-chat-toggle-thinking)
    map)
  "Keymap for `gaia-mode'.")

(define-derived-mode gaia-mode org-mode "GAIA Chat"
  "Major mode for GAIA interactive buffers, derived from Org-mode."
  (setq-local gaia-chat--stream-state nil)
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

(defun gaia-chat-buffer (&optional session-id)
  "Get or create a GAIA buffer for SESSION-ID."
  (let* ((sid (or session-id
                  (and (eq major-mode 'gaia-mode) gaia-chat--session-id)
                  (format "gaia-%d" (time-convert nil 'integer))))
         (buf-name (format "*gaia-%s*" sid))
         (buf (get-buffer-create buf-name)))
    (with-current-buffer buf
      (unless (eq major-mode 'gaia-mode)
        (gaia-mode)
        (setq-local gaia-chat--session-id sid)
        (gaia-chat--initialize-buffer)))
    buf))

(defun gaia-chat--lock-history ()
  "Lock the history in the current buffer, making everything up to the prompt read-only."
  (let ((inhibit-read-only t))
    (save-excursion
      (add-text-properties (point-min) (point-max) '(read-only t))
      (goto-char (point-max))
      (when (search-backward "GAIA > " nil t)
        (remove-text-properties (match-end 0) (point-max) '(read-only nil))))))

(defun gaia-chat--initialize-buffer ()
  "Set up the initial contents of the GAIA buffer."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert "* GAIA Agent Session\n")
    (insert "Welcome to GNU AI Assistant (GAIA) in Emacs.\n")
    (insert "Active Session: " (or gaia-chat--session-id "") "\n")
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
                           '(read-only t rear-nonsticky t face bold)))
    (gaia-chat--lock-history)))

(defun gaia-chat-send ()
  "Send the text written after the prompt to the GAIA server."
  (interactive)
  (unless (derived-mode-p 'gaia-mode)
    (user-error "This command can only be used in a GAIA Chat buffer"))
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
              (add-text-properties (point-min) (point-max) '(read-only t))
              ;; Start connection if not active
              (unless (gaia-connected-p)
                (gaia-connect)
                ;; Send session command immediately
                (gaia-send `(session ,gaia-chat--session-id ,(expand-file-name default-directory)))
                ;; Accept output to let socket process the queue
                (accept-process-output gaia-connection-process 0.1))
              ;; Send command
              (setq gaia-chat--active-request t)
              (gaia-send `(eval ,input))
              (setq gaia-chat--stream-state nil)
              (message "Prompt sent to GAIA..."))))))))

(defun gaia-chat-interrupt ()
  "Interrupt the active GAIA agent."
  (interactive)
  (unless (derived-mode-p 'gaia-mode)
    (user-error "This command can only be used in a GAIA Chat buffer"))
  (when (gaia-connected-p)
    (gaia-send '(interrupt))
    (message "Sent interrupt to GAIA server.")))

(defun gaia-chat-clear ()
  "Clear current environment and history."
  (interactive)
  (unless (derived-mode-p 'gaia-mode)
    (user-error "This command can only be used in a GAIA Chat buffer"))
  (when (gaia-connected-p)
    (gaia-send '(clear))
    (message "Cleared GAIA history.")))

(defvar gaia-chat--pending-sessions nil
  "Stash for active session list retrieved from server.")

(defvar gaia-chat--pending-thinking nil
  "Stash for active thinking mode retrieved from server.")

(defun gaia-chat-switch-session ()
  "Switch to another session ID by listing server sessions."
  (interactive)
  (unless (gaia-connected-p)
    (gaia-connect))
  (setq gaia-chat--pending-sessions 'waiting)
  (gaia-send '(list-sessions))
  ;; Wait for server response
  (let ((start-time (float-time)))
    (while (and (eq gaia-chat--pending-sessions 'waiting)
                (< (- (float-time) start-time) 5))
      (accept-process-output gaia-connection-process 0.05)))
  (if (eq gaia-chat--pending-sessions 'waiting)
      (error "Failed to retrieve sessions list from server")
    (let* ((sessions gaia-chat--pending-sessions)
           (chosen (completing-read "Select session: " sessions nil t)))
      (when (and chosen (not (string-empty-p chosen)))
        ;; Check if buffer already exists for this session
        (let ((buf (get-buffer (format "*gaia-%s*" chosen))))
          (if buf
              (pop-to-buffer buf)
            ;; Create new buffer for this session
            (let ((new-buf (gaia-chat-buffer chosen)))
              (pop-to-buffer new-buf)
              (unless (gaia-connected-p)
                (gaia-connect))
              (gaia-send `(session ,chosen ,(expand-file-name default-directory)))
              (gaia-send '(get-history))
              (message "Restored session %s" chosen))))))))

(defun gaia-chat--ensure-connected ()
  "Ensure process is connected and the session ID is initialized on the server."
  (unless (gaia-connected-p)
    (gaia-connect)
    ;; Send session command immediately
    (gaia-send `(session ,gaia-chat--session-id ,(expand-file-name default-directory)))
    ;; Accept output to let socket process the queue
    (accept-process-output gaia-connection-process 0.1)))

(defvar gaia-chat--pending-config nil
  "Stash for synchronous config operation results.")

(defun gaia-chat--send-config-cmd (sexp)
  "Send config SEXP to the GAIA server and wait silently for the final response."
  (gaia-chat--ensure-connected)
  (setq gaia-chat--pending-config 'waiting)
  (let* ((old-cell (assoc 'final gaia-connection-handlers))
         (old-handler (and old-cell (cdr old-cell))))
    ;; Temporarily override 'final handler to capture the response silently
    (gaia-connection-register-handler
     'final
     (lambda (val)
       (setq gaia-chat--pending-config val)))
    (unwind-protect
        (progn
          (gaia-send sexp)
          ;; Wait for response
          (let ((start-time (float-time)))
            (while (and (eq gaia-chat--pending-config 'waiting)
                        (< (- (float-time) start-time) 5))
              (accept-process-output gaia-connection-process 0.05)))
          (if (eq gaia-chat--pending-config 'waiting)
              (error "Configuration command timed out: %S" sexp)
            (message "%s" gaia-chat--pending-config)))
      ;; Restore original handler
      (if old-cell
          (setcdr old-cell old-handler)
        (gaia-connection-unregister-handler 'final)))))

(defun gaia-chat-toggle-thinking ()
  "Toggle model thinking mode on the GAIA server."
  (interactive)
  (unless (derived-mode-p 'gaia-mode)
    (user-error "This command can only be used in a GAIA Chat buffer"))
  (gaia-chat--ensure-connected)
  (setq gaia-chat--pending-thinking 'waiting)
  (gaia-send '(get-thinking))
  ;; Wait for server response
  (let ((start-time (float-time)))
    (while (and (eq gaia-chat--pending-thinking 'waiting)
                (< (- (float-time) start-time) 5))
      (accept-process-output gaia-connection-process 0.05)))
  (if (eq gaia-chat--pending-thinking 'waiting)
      (error "Failed to retrieve thinking mode from server")
    (let* ((current-state gaia-chat--pending-thinking)
           (new-state (if (string= current-state "on") "off" "on")))
      (gaia-chat--send-config-cmd `(set-thinking ,new-state)))))

(defun gaia-chat-set-thinking (state)
  "Set model thinking mode to STATE (on or off) on the GAIA server."
  (interactive
   (progn
     (unless (derived-mode-p 'gaia-mode)
       (user-error "This command can only be used in a GAIA Chat buffer"))
     (list (completing-read "Set model thinking mode: " '("on" "off") nil t))))
  (unless (derived-mode-p 'gaia-mode)
    (user-error "This command can only be used in a GAIA Chat buffer"))
  (if (not (member state '("on" "off")))
      (error "Invalid state: %s. Must be 'on' or 'off'" state)
    (gaia-chat--send-config-cmd `(set-thinking ,state))))

(defun gaia-chat-check-thinking ()
  "Check the current model thinking mode on the GAIA server."
  (interactive)
  (unless (derived-mode-p 'gaia-mode)
    (user-error "This command can only be used in a GAIA Chat buffer"))
  (gaia-chat--ensure-connected)
  (setq gaia-chat--pending-thinking 'waiting)
  (gaia-send '(get-thinking))
  ;; Wait for server response
  (let ((start-time (float-time)))
    (while (and (eq gaia-chat--pending-thinking 'waiting)
                (< (- (float-time) start-time) 5))
      (accept-process-output gaia-connection-process 0.05)))
  (if (eq gaia-chat--pending-thinking 'waiting)
      (error "Failed to retrieve thinking mode from server")
    (message "GAIA thinking mode is: %s" gaia-chat--pending-thinking)))

(defun gaia-chat--on-thinking-info (state)
  "Callback when thinking mode is received from server."
  (setq gaia-chat--pending-thinking state)
  (message "GAIA thinking mode is %s" state))

(defvar gaia-chat--pending-models nil
  "Stash for active models list retrieved from server.")

(defun gaia-chat-switch-model ()
  "Switch the active model on the GAIA server for this session."
  (interactive)
  (unless (derived-mode-p 'gaia-mode)
    (user-error "This command can only be used in a GAIA Chat buffer"))
  (gaia-chat--ensure-connected)
  (setq gaia-chat--pending-models 'waiting)
  (gaia-send '(list-models))
  ;; Wait for server response
  (let ((start-time (float-time)))
    (while (and (eq gaia-chat--pending-models 'waiting)
                (< (- (float-time) start-time) 5))
      (accept-process-output gaia-connection-process 0.05)))
  (if (eq gaia-chat--pending-models 'waiting)
      (error "Failed to retrieve models list from server")
    (let* ((models gaia-chat--pending-models)
           (chosen (completing-read "Select model: " models nil t)))
      (when (and chosen (not (string-empty-p chosen)))
        (gaia-chat--send-config-cmd `(set-model ,chosen))))))

(defun gaia-chat--on-models-list (models)
  "Callback when list of models is received."
  (setq gaia-chat--pending-models models))

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
  (with-current-buffer (current-buffer)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert "*** Environment Output\n")
      (insert "#+RESULTS:\n: " (replace-regexp-in-string "\n" "\n: " result) "\n\n")
      (gaia-chat--scroll-to-bottom))))

(defun gaia-chat--on-repl-error (err)
  "Insert REPL error."
  (with-current-buffer (current-buffer)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert "*** Environment Error\n")
      (insert "#+RESULTS:\n: ERROR: " (replace-regexp-in-string "\n" "\n: " err) "\n\n")
      (gaia-chat--scroll-to-bottom))))

(defun gaia-chat--on-session-list (sessions)
  "Callback when list of sessions is received."
  (setq gaia-chat--pending-sessions sessions))

(defun gaia-chat--on-history-list (history)
  "Render the full history list in the buffer."
  (with-current-buffer (current-buffer)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert "* GAIA Agent Session\n")
      (insert "Welcome to GNU AI Assistant (GAIA) in Emacs.\n")
      (insert "Active Session: " gaia-chat--session-id "\n\n")
      (dolist (turn history)
        (let* ((role (assoc-default "role" turn))
               (content (assoc-default "content" turn)))
          (cond
           ((string= role "user")
            (insert (format "** User\n%s\n\n" content)))
           ((string= role "user-repl")
            (insert (format "** User (REPL)\n%s\n\n" content)))
           ((string= role "assistant")
            (insert (format "** Assistant\n%s\n\n" content)))
           (t nil))))
      (gaia-chat--insert-prompt)
      (gaia-chat--scroll-to-bottom))))

(defun gaia-chat--on-repl-result (val)
  "Handle a successful manual REPL execution."
  ;; 1. Update the REPL buffer if active
  (when (and gaia-chat--repl-buffer (buffer-live-p gaia-chat--repl-buffer))
    (with-current-buffer gaia-chat--repl-buffer
      (when (fboundp 'gaia-repl--on-result)
        (gaia-repl--on-result val))))
  ;; 2. Update the chat buffer
  (with-current-buffer (current-buffer)
    (let ((inhibit-read-only t)
          (prompt-pos (save-excursion
                        (goto-char (point-max))
                        (search-backward "GAIA > " nil t)))
          (user-input ""))
      (when prompt-pos
        (setq user-input (buffer-substring-no-properties (+ prompt-pos 7) (point-max)))
        (delete-region prompt-pos (point-max)))
      (goto-char (point-max))
      (insert "*** REPL Environment Output (User)\n")
      (insert "#+RESULTS:\n: " (replace-regexp-in-string "\n" "\n: " val) "\n\n")
      (gaia-chat--insert-prompt)
      (when (not (string-empty-p user-input))
        (insert user-input))
      (gaia-chat--scroll-to-bottom))))

(defun gaia-chat--on-repl-result-error (err)
  "Handle a failed manual REPL execution."
  ;; 1. Update the REPL buffer if active
  (when (and gaia-chat--repl-buffer (buffer-live-p gaia-chat--repl-buffer))
    (with-current-buffer gaia-chat--repl-buffer
      (when (fboundp 'gaia-repl--on-error)
        (gaia-repl--on-error err))))
  ;; 2. Update the chat buffer
  (with-current-buffer (current-buffer)
    (let ((inhibit-read-only t)
          (prompt-pos (save-excursion
                        (goto-char (point-max))
                        (search-backward "GAIA > " nil t)))
          (user-input ""))
      (when prompt-pos
        (setq user-input (buffer-substring-no-properties (+ prompt-pos 7) (point-max)))
        (delete-region prompt-pos (point-max)))
      (goto-char (point-max))
      (insert "*** REPL Environment Error (User)\n")
      (insert "#+RESULTS:\n: ERROR: " (replace-regexp-in-string "\n" "\n: " err) "\n\n")
      (gaia-chat--insert-prompt)
      (when (not (string-empty-p user-input))
        (insert user-input))
      (gaia-chat--scroll-to-bottom))))

(defun gaia-chat--on-final (answer)
  "Insert the final response and prepare the next prompt."
  (with-current-buffer (gaia-chat-buffer)
    (let ((inhibit-read-only t))
      (setq gaia-chat--active-request nil)
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
      (setq gaia-chat--active-request nil)
      (goto-char (point-max))
      (insert "\n*** Server Error\n" err "\n")
      (setq gaia-chat--stream-state nil)
      (gaia-chat--insert-prompt)
      (gaia-chat--scroll-to-bottom)
      (pop-to-buffer (current-buffer) '((display-buffer-reuse-window display-buffer-same-window))))))

(defun gaia-chat--on-repl-private-result (val)
  "Handle a private REPL execution result (no state change)."
  (when (and gaia-chat--repl-buffer (buffer-live-p gaia-chat--repl-buffer))
    (with-current-buffer gaia-chat--repl-buffer
      (when (fboundp 'gaia-repl--on-result)
        (gaia-repl--on-result val)))))

(defun gaia-chat--on-repl-private-result-error (err)
  "Handle a private REPL execution error (no state change)."
  (when (and gaia-chat--repl-buffer (buffer-live-p gaia-chat--repl-buffer))
    (with-current-buffer gaia-chat--repl-buffer
      (when (fboundp 'gaia-repl--on-error)
        (gaia-repl--on-error err)))))

;; Register handlers
(gaia-connection-register-handler 'token #'gaia-chat--on-token)
(gaia-connection-register-handler 'thought #'gaia-chat--on-thought)
(gaia-connection-register-handler 'status #'gaia-chat--on-status)
(gaia-connection-register-handler 'code #'gaia-chat--on-code)
(gaia-connection-register-handler 'result #'gaia-chat--on-result)
(gaia-connection-register-handler 'repl-error #'gaia-chat--on-repl-error)
(gaia-connection-register-handler 'final #'gaia-chat--on-final)
(gaia-connection-register-handler 'error #'gaia-chat--on-error)
(gaia-connection-register-handler 'session-list #'gaia-chat--on-session-list)
(gaia-connection-register-handler 'history-list #'gaia-chat--on-history-list)
(gaia-connection-register-handler 'repl-result #'gaia-chat--on-repl-result)
(gaia-connection-register-handler 'repl-result-error #'gaia-chat--on-repl-result-error)
(gaia-connection-register-handler 'repl-private-result #'gaia-chat--on-repl-private-result)
(gaia-connection-register-handler 'repl-private-result-error #'gaia-chat--on-repl-private-result-error)
(gaia-connection-register-handler 'thinking-info #'gaia-chat--on-thinking-info)
(gaia-connection-register-handler 'models-list #'gaia-chat--on-models-list)

(provide 'gaia-chat)
;;; gaia-chat.el ends here
