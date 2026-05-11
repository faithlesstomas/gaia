
;;; ob-gaia.el --- Org-Babel support for GAIA (Server-Matched Version)

(require 'ob)
(require 'json)

(defcustom ob-gaia-socket-path "/tmp/gaia.sock"
  "Path to the GAIA UNIX socket."
  :group 'ob-gaia :type 'string)

(defun org-babel-execute:gaia (body params)
  "Execute GAIA code by matching the server's expected S-expression/JSON structure."
  (let* ((session (or (cdr (assq :session params)) "default"))
         ;; Dopasowujemy do (('eval code)) lub struktury którą sugeruje server.scm
         ;; Wiele serwerów Guile JSON-RPC upraszcza strukturę do ["method", params...]
         (request `((method . "eval")
                    (params . ((code . ,body)
                               (session . ,session)))
                    (jsonrpc . "2.0")
                    (id . 1)))
         (json-msg (json-encode request))
         ;; Używamy socat z krótkim timeoutem dla gniazd UNIX
         (command (format "echo %S | socat -t 5 - UNIX-CONNECT:%s" 
                          json-msg
                          (expand-file-name ob-gaia-socket-path)))
         (raw-response (shell-command-to-string command)))
    
    (if (string-empty-p raw-response)
        (error "GAIA Error: No response from %s" ob-gaia-socket-path)
      (condition-case nil
          (let* ((json-object-type 'alist)
                 (response (json-read-from-string raw-response))
                 (result (assoc-ref response 'result))
                 (err (assoc-ref response 'error)))
            (if err
                (format "SERVER ERROR: %S" err)
              (org-babel-gaia-format-result result)))
        (error (format "Error parsing response: %s" raw-response))))))

(defun org-babel-gaia-format-result (val)
  "Format result for Org-mode buffer."
  (cond
   ((null val) "nil")
   ((eq val t) "t")
   ((vectorp val) (mapconcat #'identity (append val nil) "\n"))
   ((listp val) (format "%S" val))
   (t (format "%s" val))))

(add-to-list 'org-src-lang-modes '("gaia" . scheme))
(provide 'ob-gaia)
