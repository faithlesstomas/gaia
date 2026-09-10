;;; gaia-chat.el --- Interactive Org-Mode Chat Interface for GAIA -*- lexical-binding: t; -*-

;; Author: Tomasz
;; Keywords: comm, processes, hypermedia

;;; Commentary:
;; Provides a derived org-mode buffer for interacting with the GAIA agent.
;; Handles streaming tokens, folding thoughts, rendering errors, and sending prompts.

;;; Code:

(require 'org)
(require 'pp)
(require 'gaia-connection)

(defgroup gaia-chat nil
  "Interactive chat buffer for GAIA."
  :group 'gaia
  :prefix "gaia-chat-")

(defvar-local gaia-chat--stream-state nil
  "Current streaming state: nil, \\='token, \\='thought.")

(defvar-local gaia-chat--stream-start-pos nil
  "Marker tracking the starting position of the token stream.")

(defvar-local gaia-chat--session-id nil
  "Active session ID in the buffer.")

(defvar-local gaia-chat--repl-buffer nil
  "The REPL buffer associated with this chat buffer.")

(defvar-local gaia-chat--active-request nil
  "Non-nil if the Assistant is currently running a request.")

(defvar-local gaia-chat--code-executed nil
  "Non-nil if code was executed during the current request cycle.")

(defvar-local gaia-chat--model nil
  "Active model reported by the GAIA server for this chat buffer.")

(defvar-local gaia-chat--thinking-mode nil
  "Active thinking mode reported by the GAIA server for this chat buffer.")

(defvar-local gaia-chat--last-enabled-thinking "on"
  "Last enabled thinking mode, restored after toggling thinking back on.")

(defun gaia-chat--valid-session-id-p (value)
  "Return non-nil when VALUE is a safe durable GAIA session identifier."
  (and (stringp value)
       (> (length value) 0)
       (<= (length value) 128)
       (string-match-p "\\`[[:alnum:]_.-]+\\'" value)))

(defun gaia-chat--last-session-id ()
  "Read the last logical GAIA session from the project boundary."
  (let ((path (expand-file-name ".last_session" (gaia--find-project-root))))
    (when (file-readable-p path)
      (with-temp-buffer
        (insert-file-contents path)
        (let ((value (string-trim (buffer-string))))
          (and (gaia-chat--valid-session-id-p value) value))))))

(defun gaia-chat--model-supports-thinking-p (model)
  "Return non-nil when MODEL is recognized as supporting thinking."
  (when model
    (let ((name (downcase model)))
      (or (string-match-p "think" name)
          (string-match-p "r1" name)
          (string-match-p "qwen3" name)
          (string-match-p "gpt-oss" name)
          (string-match-p "gemma4" name)
          (string-match-p "reasoning" name)
          (string-match-p "gemini" name)
          (string-match-p "claude" name)))))

(defun gaia-chat--mode-line-info ()
  "Build the GAIA session information shown in the mode line."
  (let* ((connection-state (cond
                            (gaia-chat--active-request "running")
                            ((gaia-connected-p) "ready")
                            (t "offline")))
         (thinking (when (gaia-chat--model-supports-thinking-p gaia-chat--model)
                     (format " think:%s" (or gaia-chat--thinking-mode "?")))))
    (format "  [session:%s model:%s%s %s]"
            (or gaia-chat--session-id "?")
            (or gaia-chat--model "?")
            (or thinking "")
            connection-state)))

(defun gaia-chat--refresh-mode-line ()
  "Refresh mode-line state in the current GAIA chat buffer."
  (force-mode-line-update t))

(defun gaia-chat--canonical-thinking-state (state)
  "Return the canonical display spelling for thinking STATE."
  (cond
   ((member state '("off" "false")) "off")
   ((member state '("on" "true")) "on")
   (t state)))

(defun gaia-chat--record-thinking-state (state)
  "Record thinking STATE and remember it when it is enabled."
  (let ((canonical (gaia-chat--canonical-thinking-state state)))
    (setq gaia-chat--thinking-mode canonical)
    (when (and canonical (not (string= canonical "off")))
      (setq gaia-chat--last-enabled-thinking canonical))
    (gaia-chat--refresh-mode-line)))

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
  (setq-local gaia-chat--model nil)
  (setq-local gaia-chat--thinking-mode nil)
  (setq-local gaia-chat--last-enabled-thinking "on")
  (setq-local mode-line-format
              (append '((:eval (gaia-chat--mode-line-info))) mode-line-format))
  (add-hook 'gaia-connection-on-close-hooks #'gaia-chat--refresh-mode-line nil t)
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
                  (gaia-chat--last-session-id)
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
      (goto-char (point-max))
      (when (search-backward "GAIA > " nil t)
        (let ((prompt-end (match-end 0)))
          (add-text-properties (point-min) prompt-end '(read-only t))
          (add-text-properties (match-beginning 0) prompt-end '(rear-nonsticky t))
          (remove-text-properties prompt-end (point-max) '(read-only nil)))))))

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

(defun gaia-chat--input-message (input)
  "Translate user input into the public GAIA cognitive protocol.
Normal text starts a memory-backed GCAS conversation. Executable Goals,
one-shot legacy chat, direct execution, and investigation are opt-in commands."
  (cond
   ((string-prefix-p "/chat " input) `(converse ,(string-trim (substring input 6))))
   ((string-prefix-p "/converse " input) `(converse ,(string-trim (substring input 10))))
   ((string-prefix-p "/solve " input) `(solve ,(string-trim (substring input 7))))
   ((string-prefix-p "/investigate " input) `(investigate ,(string-trim (substring input 13))))
   ((string-prefix-p "/ask " input) `(ask ,(string-trim (substring input 5))))
   ((string-prefix-p "/eval " input) `(repl ,(string-trim (substring input 6))))
   ((string= input "/cognitive-events") '(get-cognitive-events))
   ((member input '("/cognitive-state" "/cognitive-objects")) '(get-cognitive-state))
   ;; Other slash commands remain server-owned for compatibility.
   ((string-prefix-p "/" input) `(eval ,input))
   (t `(converse ,input))))

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
                (gaia-chat--request-server-info)
                ;; Accept output to let socket process the queue
                (accept-process-output gaia-connection-process 0.1))
              ;; Send command
              (setq gaia-chat--active-request t)
              (gaia-chat--refresh-mode-line)
              (setq gaia-chat--code-executed nil)
              (gaia-send (gaia-chat--input-message input))
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

(defconst gaia-chat-thinking-states
  '("off" "on" "false" "true" "low" "medium" "high" "max")
  "Thinking modes accepted by the GAIA server.")

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
              (gaia-chat--request-server-info)
              (gaia-send '(get-history))
              (message "Restored session %s" chosen))))))))

(defun gaia-chat--ensure-connected ()
  "Ensure process is connected and the session ID is initialized on the server."
  (unless (gaia-connected-p)
    (gaia-connect)
    ;; Send session command immediately
    (gaia-send `(session ,gaia-chat--session-id ,(expand-file-name default-directory)))
    (gaia-chat--request-server-info)
    ;; Accept output to let socket process the queue
    (accept-process-output gaia-connection-process 0.1)))

(defun gaia-chat--request-server-info ()
  "Request model and thinking state for the current chat session."
  (gaia-send '(get-model))
  (gaia-send '(get-thinking)))

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
           (canonical (gaia-chat--canonical-thinking-state current-state))
           (new-state (if (string= canonical "off")
                          gaia-chat--last-enabled-thinking
                        "off")))
      (gaia-chat--send-config-cmd `(set-thinking ,new-state))
      (gaia-chat--record-thinking-state new-state))))

(defun gaia-chat-set-thinking (state)
  "Set model thinking mode to STATE on the GAIA server.
STATE may enable or disable thinking, or select an Ollama effort level."
  (interactive
   (progn
     (unless (derived-mode-p 'gaia-mode)
       (user-error "This command can only be used in a GAIA Chat buffer"))
     (list (completing-read "Set model thinking mode: " gaia-chat-thinking-states nil t))))
  (unless (derived-mode-p 'gaia-mode)
    (user-error "This command can only be used in a GAIA Chat buffer"))
  (if (not (member state gaia-chat-thinking-states))
      (error "Invalid thinking mode: %s" state)
    (gaia-chat--send-config-cmd `(set-thinking ,state))
    (gaia-chat--record-thinking-state state)))

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
  (gaia-chat--record-thinking-state state)
  (message "GAIA thinking mode is %s" state))

(defvar gaia-chat--pending-models nil
  "Stash for active models list retrieved from server.")

(defun gaia-chat-set-model (model)
  "Set MODEL as the active model for the current GAIA chat session."
  (interactive
   (progn
     (unless (derived-mode-p 'gaia-mode)
       (user-error "This command can only be used in a GAIA Chat buffer"))
     (list (read-string "Set GAIA model: " gaia-chat--model))))
  (unless (derived-mode-p 'gaia-mode)
    (user-error "This command can only be used in a GAIA Chat buffer"))
  (unless (and (stringp model) (not (string-empty-p (string-trim model))))
    (user-error "Model name cannot be empty"))
  (let ((model-name (string-trim model)))
    (gaia-chat--send-config-cmd `(set-model ,model-name))
    (setq gaia-chat--model model-name)
    (gaia-chat--refresh-mode-line)))

(defun gaia-chat-switch-model ()
  "Select the active model from models advertised by the GAIA server."
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
        (gaia-chat-set-model chosen)))))

(defun gaia-chat--on-model-info (model)
  "Record the active MODEL reported by the GAIA server."
  (setq gaia-chat--model model)
  (gaia-chat--refresh-mode-line))

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
        (setq gaia-chat--stream-start-pos (point-marker))
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
  "Insert executing code block, cleaning raw code from streamed response."
  (with-current-buffer (gaia-chat-buffer)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (when (eq gaia-chat--stream-state 'thought)
        (insert "\n#+END_QUOTE\n\n"))
      ;; Clean raw code blocks from the streamed response text
      (when (and gaia-chat--stream-start-pos
                 (markerp gaia-chat--stream-start-pos)
                 (marker-position gaia-chat--stream-start-pos))
        (let* ((start (marker-position gaia-chat--stream-start-pos))
               (raw-text (buffer-substring-no-properties start (point-max)))
               ;; Remove ALL ```repl...``` and ```wisp...``` blocks from streamed text
               (cleaned (replace-regexp-in-string
                         "```\\(?:repl\\|wisp\\)\\(?:\n\\|.\\)*?```" ""
                         raw-text))
               (cleaned (string-trim cleaned)))
          (delete-region start (point-max))
          (goto-char start)
          (when (and cleaned (not (string-empty-p cleaned)))
            (insert cleaned "\n\n"))
          (set-marker gaia-chat--stream-start-pos nil)
          (setq gaia-chat--stream-start-pos nil)))
      (setq gaia-chat--stream-state nil)
      (setq gaia-chat--code-executed t)
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

(defun gaia-chat--on-notebook-done (_val)
  "Handle notebook-done event: code was executed successfully, just insert the prompt."
  (with-current-buffer (gaia-chat-buffer)
    (let ((inhibit-read-only t))
      (setq gaia-chat--active-request nil)
      (gaia-chat--refresh-mode-line)
      (setq gaia-chat--stream-state nil)
      (setq gaia-chat--code-executed nil)
      (gaia-chat--insert-prompt)
      ;; Also catches model/thinking changes made through typed slash commands.
      (gaia-chat--request-server-info)
      (gaia-chat--scroll-to-bottom)
      (pop-to-buffer (current-buffer) '((display-buffer-reuse-window display-buffer-same-window))))))

(defun gaia-chat--on-final (answer)
  "Insert the final response and prepare the next prompt."
  (with-current-buffer (gaia-chat-buffer)
    (let ((inhibit-read-only t))
      (setq gaia-chat--active-request nil)
      (gaia-chat--refresh-mode-line)
      (goto-char (point-max))
      (when (eq gaia-chat--stream-state 'thought)
        (insert "\n#+END_QUOTE\n\n"))
      (cond
       ;; Case 1: Token stream is active — replace streamed tokens with clean answer
       ((and (eq gaia-chat--stream-state 'token)
             gaia-chat--stream-start-pos
             (markerp gaia-chat--stream-start-pos)
             (buffer-live-p (marker-buffer gaia-chat--stream-start-pos)))
        (delete-region gaia-chat--stream-start-pos (point-max))
        (insert answer "\n")
        (set-marker gaia-chat--stream-start-pos nil)
        (setq gaia-chat--stream-start-pos nil))
       ;; Case 2: Code was executed during this cycle — don't add a redundant heading
       (gaia-chat--code-executed
        (unless (string-empty-p answer)
          (insert "\n*** Assistant\n" answer "\n")))
       ;; Case 3: Pure conversational reply — show as Final Answer
       (t
        (insert "\n*** Final Answer\n" answer "\n")))
      (setq gaia-chat--stream-state nil)
      (setq gaia-chat--code-executed nil)
      (gaia-chat--insert-prompt)
      (gaia-chat--scroll-to-bottom)
      (pop-to-buffer (current-buffer) '((display-buffer-reuse-window display-buffer-same-window))))))

(defun gaia-chat--on-error (err)
  "Insert server error."
  (with-current-buffer (gaia-chat-buffer)
    (let ((inhibit-read-only t))
      (setq gaia-chat--active-request nil)
      (gaia-chat--refresh-mode-line)
      (goto-char (point-max))
      (insert "\n*** Server Error\n" err "\n")
      (setq gaia-chat--stream-state nil)
      (gaia-chat--insert-prompt)
      (gaia-chat--scroll-to-bottom)
      (pop-to-buffer (current-buffer) '((display-buffer-reuse-window display-buffer-same-window))))))

(defun gaia-chat--on-cognitive-events (events)
  "Render the session event trace supplied by the GCAS server."
  (with-current-buffer (gaia-chat-buffer)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert "\n*** GCAS Event Trace\n#+BEGIN_EXAMPLE\n"
              (format "%S" events) "\n#+END_EXAMPLE\n")
      (gaia-chat--scroll-to-bottom))))

(defun gaia-chat--on-cognitive-state (state)
  "Render Goal, Control, Workspace, CO, and Memory state from the server."
  (with-current-buffer (gaia-chat-buffer)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert "\n*** GCAS Cognitive State\n#+BEGIN_EXAMPLE\n"
              (pp-to-string state) "#+END_EXAMPLE\n")
      (gaia-chat--scroll-to-bottom))))

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
(gaia-connection-register-handler 'notebook-done #'gaia-chat--on-notebook-done)
(gaia-connection-register-handler 'error #'gaia-chat--on-error)
(gaia-connection-register-handler 'session-list #'gaia-chat--on-session-list)
(gaia-connection-register-handler 'history-list #'gaia-chat--on-history-list)
(gaia-connection-register-handler 'repl-result #'gaia-chat--on-repl-result)
(gaia-connection-register-handler 'repl-result-error #'gaia-chat--on-repl-result-error)
(gaia-connection-register-handler 'repl-private-result #'gaia-chat--on-repl-private-result)
(gaia-connection-register-handler 'repl-private-result-error #'gaia-chat--on-repl-private-result-error)
(gaia-connection-register-handler 'thinking-info #'gaia-chat--on-thinking-info)
(gaia-connection-register-handler 'model-info #'gaia-chat--on-model-info)
(gaia-connection-register-handler 'models-list #'gaia-chat--on-models-list)
(gaia-connection-register-handler 'cognitive-events #'gaia-chat--on-cognitive-events)
(gaia-connection-register-handler 'cognitive-state #'gaia-chat--on-cognitive-state)

(provide 'gaia-chat)
;;; gaia-chat.el ends here
