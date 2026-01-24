(add-to-load-path (string-append (dirname (current-filename)) "/../scheme"))

(use-modules (gaia core))

(display "Starting GAIA (GNU AI Assistant)...\n")
(start-gaia)
