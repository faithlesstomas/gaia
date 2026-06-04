;;; ob-gaia.el --- Org-Babel support for GAIA (Server-S-Expression Version)

;; Author: Tomasz
;; Keywords: literate programming, intelligent agents, scheme
;; Homepage: https://github.com/faithlesstomas/gaia

;;; License: MIT

;;; Commentary:
;; This package provides Org-Babel support for GAIA (GNU AI Assistant).
;; It communicates with the GAIA headless server using S-expressions over
;; a UNIX socket.

;;; Code:

(require 'ob)

(defcustom ob-gaia-socket-path "/tmp/gaia.sock"
  "Path to the GAIA UNIX socket."
  :group 'ob-gaia
  :type 'string)

(defun org-babel-gaia-parse-response (raw-response)
  "Parse the raw S-expression response from the GAIA server."
  (condition-case err
      (let* ((parsed (car (read-from-string raw-response))))
        (if (and (listp parsed) (eq (car parsed) 'repl-result))
            (let ((inner-str (cadr parsed)))
              (cond
               ((or (string= inner-str "(ok)")
                    (string= inner-str "(ok )"))
                "")
               ((string-prefix-p "(ok " inner-str)
                ;; Strip "(ok " from start and ")" from end
                (substring inner-str 4 -1))
               ((string-prefix-p "(error " inner-str)
                (error "GAIA Server Error: %s" (substring inner-str 7 -1)))
               (t inner-str)))
          (error "Unexpected response format: %s" raw-response)))
    (error (error "Error parsing GAIA response: %s (Raw: %s)"
                  (error-message-string err)
                  raw-response))))

(defun org-babel-execute:gaia (body params)
  "Execute a block of GAIA Scheme code.
BODY is the code block content.
PARAMS is the alist of header arguments."
  (let* ((session (or (cdr (assq :session params)) "default"))
         (session-str (replace-regexp-in-string "\n" "\\n" (prin1-to-string session) t t))
         (body-str (replace-regexp-in-string "\n" "\\n" (prin1-to-string body) t t))
         (msg (format "(session %s)\n(repl %s)\n" session-str body-str))
         (socket-file (expand-file-name ob-gaia-socket-path))
         (raw-response
          (with-temp-buffer
            (insert msg)
            (let ((exit-code
                   (call-process-region (point-min) (point-max)
                                        "socat" t t nil
                                        "-t" "5" "-"
                                        (format "UNIX-CONNECT:%s" socket-file))))
              (if (/= exit-code 0)
                  (error "socat failed to connect to GAIA server at %s (exit code %d): %s"
                         socket-file exit-code (buffer-string))
                (buffer-string))))))
    (org-babel-gaia-parse-response raw-response)))

(add-to-list 'org-src-lang-modes '("gaia" . scheme))

(provide 'ob-gaia)

;;; ob-gaia.el ends here
