;;; ob-gaia.el --- Org-Babel Support for GAIA -*- lexical-binding: t; -*-

;; Author: Tomasz
;; Keywords: literate programming, scheme, agents

;;; Commentary:
;; Org-Babel integration for GAIA. Supports:
;; - :eval repl (default) - execute Scheme directly in GAIA REPL
;; - :eval ask - send natural language prompt to GAIA agent
;; - :session session-name - specify session context

;;; Code:

(require 'ob)
(require 'gaia-connection)

(defgroup ob-gaia nil
  "Org-Babel settings for GAIA."
  :group 'org-babel
  :prefix "ob-gaia-")

(defvar ob-gaia--result nil
  "Internal variable to store sync evaluation response.")

(defvar ob-gaia--status nil
  "Internal variable to store sync evaluation status: \\='waiting, \\='success, \\='error.")

(defvar ob-gaia-in-progress nil
  "Dynamic variable bound to t when Org-Babel GAIA is executing.")

(defun org-babel-execute:gaia (body params)
  "Execute a block of GAIA Scheme code.
BODY is the code block content.
PARAMS is the alist of header arguments."
  (let* ((ob-gaia-in-progress t)
         (session (or (cdr (assq :session params)) "default"))
         (session-id (cond
                       ((stringp session) session)
                       ((symbolp session) (symbol-name session))
                       (t "default")))
         (eval-mode (or (cdr (assq :eval params)) "repl"))
         (timeout (or (and (cdr (assq :timeout params))
                           (string-to-number (cdr (assq :timeout params))))
                      30))
         (clean-body (string-trim body)))
    
    (unless (gaia-connected-p)
      (gaia-connect)
      ;; Bind session ID
      (gaia-send `(session ,session-id)))
    
    ;; Synchronous evaluation using connection filter
    (setq ob-gaia--result nil)
    (setq ob-gaia--status 'waiting)
    
    ;; Register temporary event handlers to capture the execution result
    (let ((old-repl-result (assoc 'repl-result gaia-connection-handlers))
          (old-final (assoc 'final gaia-connection-handlers))
          (old-error (assoc 'error gaia-connection-handlers)))
      
      (gaia-connection-register-handler
       'repl-result
       (lambda (val)
         (setq ob-gaia--result val)
         (setq ob-gaia--status 'success)))
      
      (gaia-connection-register-handler
       'final
       (lambda (val)
         (setq ob-gaia--result val)
         (setq ob-gaia--status 'success)))
      
      (gaia-connection-register-handler
       'error
       (lambda (val)
         (setq ob-gaia--result val)
         (setq ob-gaia--status 'error)))
      
      (unwind-protect
          (progn
            ;; Send request to server
            (if (string= eval-mode "ask")
                (gaia-send `(eval ,clean-body))
              (gaia-send `(repl ,clean-body)))
            
            ;; Wait loop
            (let ((start-time (float-time)))
              (while (and (eq ob-gaia--status 'waiting)
                          (< (- (float-time) start-time) timeout))
                (accept-process-output gaia-connection-process 0.05)))
            
            (cond
             ((eq ob-gaia--status 'waiting)
              (error "GAIA execution timed out after %d seconds" timeout))
             ((eq ob-gaia--status 'error)
              (error "GAIA Execution Error: %s" ob-gaia--result))
             (t ob-gaia--result)))
        
        ;; Restore original handlers
        (if old-repl-result
            (setcdr (assoc 'repl-result gaia-connection-handlers) (cdr old-repl-result))
          (gaia-connection-unregister-handler 'repl-result))
        
        (if old-final
            (setcdr (assoc 'final gaia-connection-handlers) (cdr old-final))
          (gaia-connection-unregister-handler 'final))
        
        (if old-error
            (setcdr (assoc 'error gaia-connection-handlers) (cdr old-error))
          (gaia-connection-unregister-handler 'error))))))

;; Associate gaia blocks with scheme editing mode
(add-to-list 'org-src-lang-modes '("gaia" . scheme))

(provide 'ob-gaia)
;;; ob-gaia.el ends here
