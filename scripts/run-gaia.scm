(add-to-load-path (string-append (dirname (current-filename)) "/../src"))

(use-modules (gaia core))

(display "Starting GAIA (GNU AI Assistant)...\n")
(start-gaia)
