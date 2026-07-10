;;; gaia-connection.el --- UNIX Socket Connection Layer for GAIA -*- lexical-binding: t; -*-

;; Author: Tomasz
;; Keywords: comm, processes

;;; Commentary:
;; Manages the persistent UNIX socket connection to the GAIA server,
;; parses incoming newline-delimited S-expressions, and handles event dispatching.

;;; Code:

(require 'cl-lib)

(defgroup gaia-connection nil
  "Connection settings for GAIA."
  :group 'gaia
  :prefix "gaia-connection-")

(defcustom gaia-connection-socket-path "/tmp/gaia.sock"
  "Path to the GAIA UNIX socket."
  :type 'string
  :group 'gaia-connection)

(defvar-local gaia-connection-process nil
  "The active network process connecting to GAIA.")

(defvar-local gaia-connection-buffer ""
  "Buffer to accumulate partial S-expressions from the process.")

(defvar gaia-connection-handlers nil
  "Alists of event type symbols to handler functions.")

(defvar gaia-connection-on-close-hooks nil
  "Hooks called when the connection closes.")

(defun gaia-connection-register-handler (event-type handler)
  "Register HANDLER to be called when EVENT-TYPE is received."
  (let ((existing (assoc event-type gaia-connection-handlers)))
    (if existing
        (setcdr existing handler)
      (push (cons event-type handler) gaia-connection-handlers))))

(defun gaia-connection-unregister-handler (event-type)
  "Unregister handler for EVENT-TYPE."
  (setq gaia-connection-handlers
        (cl-delete event-type gaia-connection-handlers :key #'car)))

(defun gaia-connected-p ()
  "Return non-nil if connected to GAIA."
  (and gaia-connection-process
       (eq (process-status gaia-connection-process) 'open)))

(defun gaia-connect (&optional socket-path)
  "Establish a persistent UNIX socket connection to GAIA."
  (interactive)
  (let ((path (or socket-path gaia-connection-socket-path))
        (chat-buf (current-buffer)))
    (when (gaia-connected-p)
      (gaia-disconnect))
    (setq-local gaia-connection-buffer "")
    (message "Connecting to GAIA server at %s..." path)
    (condition-case err
        (let ((proc (make-network-process
                     :name (format "gaia-connection-%s" (buffer-name))
                     :family 'local
                     :service path
                     :filter #'gaia-connection--process-filter
                     :sentinel #'gaia-connection--process-sentinel
                     :coding 'utf-8)))
          (process-put proc 'gaia-buffer chat-buf)
          (setq-local gaia-connection-process proc)
          (message "GAIA connection established.")
          proc)
      (error
       (setq-local gaia-connection-process nil)
       (error "Failed to connect to GAIA at %s: %s" path (error-message-string err))))))

(defun gaia-disconnect ()
  "Disconnect from the GAIA server."
  (interactive)
  (when gaia-connection-process
    (message "Disconnecting from GAIA...")
    (delete-process gaia-connection-process)
    (setq gaia-connection-process nil)
    (message "Disconnected from GAIA.")))

(defun gaia-send (sexp)
  "Send SEXP (a Lisp object) to the GAIA server as a serialized S-expression."
  (unless (gaia-connected-p)
    ;; Auto-connect
    (gaia-connect))
  (let* ((print-escape-newlines t)
         (print-level nil)
         (print-length nil)
         (serialized (format "%S" sexp))
         ;; Standardize boolean representation: elisp writes t/nil, server expects #t/#f
         (formatted (replace-regexp-in-string "\\bnil\\b" "#f" serialized))
         (formatted (replace-regexp-in-string "\\bt\\b" "#t" formatted))
         (msg (concat formatted "\n")))
    ;; Write to debug log file
    (with-temp-buffer
      (insert (format "[%s] SENT: %s" (format-time-string "%Y-%m-%d %H:%M:%S") msg))
      (write-region (point-min) (point-max) "/home/tomasz/scratch/AI/gaia/test-output.txt" t 'silent))
    (process-send-string gaia-connection-process msg)))

(defun gaia-connection--process-filter (proc string)
  "Buffer incoming raw data from PROC and split into lines."
  (let ((buf (process-get proc 'gaia-buffer)))
    (when (and buf (buffer-live-p buf))
      (with-current-buffer buf
        (setq gaia-connection-buffer (concat gaia-connection-buffer string))
        (let ((lines (split-string gaia-connection-buffer "\n")))
          ;; The last element might be incomplete; keep it in the buffer
          (setq gaia-connection-buffer (car (last lines)))
          ;; Process all complete lines
          (dolist (line (butlast lines))
            (unless (string-empty-p (string-trim line))
              (gaia-connection--handle-line line))))))))

(defun gaia-connection--handle-line (line)
  "Convert LINE to Lisp data and dispatch it."
  (condition-case err
      (let* (;; Pre-process scheme syntax so elisp read can handle it:
             ;; Translate #t -> t, #f -> nil
             (elisp-compatible (replace-regexp-in-string "#t" "t" line))
             (elisp-compatible (replace-regexp-in-string "#f" "nil" elisp-compatible))
             (parsed (car (read-from-string elisp-compatible))))
        (gaia-connection--dispatch parsed))
    (error
     (message "GAIA S-expr read error: %s (Raw: %s)" (error-message-string err) line))))

(defun gaia-connection--dispatch (event)
  "Dispatch the parsed EVENT to registered handlers."
  (when (and (listp event) (symbolp (car event)))
    (let* ((event-type (car event))
           (args (cdr event))
           (handler (assoc event-type gaia-connection-handlers)))
      (if handler
          (apply (cdr handler) args)
        ;; Fallback logging for unhandled events
        (when (member event-type '(error repl-error))
          (message "GAIA Server Error: %S" args))))))

(defun gaia-connection--process-sentinel (proc event)
  "Handle process lifecycle events."
  (when (member event '("finished\n" "exited\n" "connection broken by remote peer\n"))
    (let ((buf (process-get proc 'gaia-buffer)))
      (when (and buf (buffer-live-p buf))
        (with-current-buffer buf
          (setq gaia-connection-process nil)
          (message "GAIA connection closed: %s" (string-trim event))
          (run-hooks 'gaia-connection-on-close-hooks))))))


(provide 'gaia-connection)
;;; gaia-connection.el ends here
