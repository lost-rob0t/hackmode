(in-package :hackmode-provider-recon)

(defun http-probe-write-out-format ()
  "Return curl's bounded probe format with literal tab delimiters."
  (format nil
          "%{http_code}~C%{url_effective}~C%{content_type}~C%{remote_ip}~C%{num_redirects}~%"
          #\Tab #\Tab #\Tab #\Tab))

(defun run-http-probe (url)
  "Run a bounded HEAD-style HTTP probe for typed URL and return one result row."
  (check-type url hackmode:url)
  (hackmode:normalize-asset url)
  (multiple-value-bind (stdout stderr exit-code)
      (uiop:run-program
       (list *http-probe-program*
             "--silent"
             "--show-error"
             "--head"
             "--location"
             "--max-time" "10"
             "--max-redirs" "5"
             "--output" "/dev/null"
             "--write-out" (http-probe-write-out-format)
             (hackmode:asset-canonical-value url))
       :output :string
       :error-output :string
       :ignore-error-status t)
    (unless (or (null exit-code) (zerop exit-code))
      (error "HTTP probe exited with status ~a: ~a"
             exit-code
             (trim-text stderr)))
    (or stdout "")))

(eval-when (:load-toplevel :execute)
  (register-http-probe-provider :runner #'run-http-probe))
