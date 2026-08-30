(in-package :hackmode-provider-recon)

(defparameter *subfinder-program*
  (or (uiop:getenv "HACKMODE_SUBFINDER_PROGRAM") "subfinder")
  "Subfinder executable used by the subdomain-enumeration provider.")

(defparameter *http-probe-program*
  (or (uiop:getenv "HACKMODE_HTTP_PROBE_PROGRAM") "curl")
  "curl-compatible executable used by the HTTP probe provider.")

(defun trim-text (value)
  (string-trim '(#\Space #\Tab #\Newline #\Return) (or value "")))

(defun normalize-domain-candidate (value)
  (let* ((trimmed (string-downcase (trim-text value)))
         (without-dot (string-right-trim '(#\.) trimmed)))
    (if (and (>= (length without-dot) 2)
             (string= "*." without-dot :end2 2))
        (subseq without-dot 2)
        without-dot)))

(defun domain-under-root-p (candidate root)
  (let* ((candidate (normalize-domain-candidate candidate))
         (root (normalize-domain-candidate root))
         (candidate-length (length candidate))
         (root-length (length root)))
    (or (string= candidate root)
        (and (> candidate-length root-length)
             (char= #\. (char candidate (- candidate-length root-length 1)))
             (string= root candidate :start2 (- candidate-length root-length))))))

(defun domain-assets-from-names (names root tool tags)
  (let ((seen (make-hash-table :test #'equal))
        assets)
    (dolist (name names)
      (let ((candidate (normalize-domain-candidate name)))
        (when (and (plusp (length candidate))
                   (not (find #\@ candidate))
                   (domain-under-root-p candidate root)
                   (not (gethash candidate seen)))
          (setf (gethash candidate seen) t)
          (push (make-instance 'hackmode:domain
                               :record candidate
                               :tool tool
                               :tags tags)
                assets))))
    (nreverse assets)))

(defun parse-subfinder-output (output root-domain)
  "Parse Subfinder newline OUTPUT into typed domains scoped beneath ROOT-DOMAIN."
  (domain-assets-from-names
   (uiop:split-string (or output "") :separator '(#\Newline #\Return))
   root-domain
   "subfinder"
   '("dns" "subfinder")))

(defun run-subfinder (domain)
  "Run Subfinder for typed DOMAIN and return its raw stdout."
  (check-type domain hackmode:domain)
  (multiple-value-bind (stdout stderr exit-code)
      (uiop:run-program
       (list *subfinder-program*
             "-silent"
             "-d"
             (hackmode:domain-name domain))
       :output :string
       :error-output :string
       :ignore-error-status t)
    (unless (or (null exit-code) (zerop exit-code))
      (error "Subfinder exited with status ~a: ~a"
             exit-code
             (trim-text stderr)))
    (or stdout "")))

(defun subfinder-enumerate (domain &key (runner #'run-subfinder))
  "Enumerate subdomains for typed DOMAIN through RUNNER."
  (check-type domain hackmode:domain)
  (parse-subfinder-output
   (funcall runner domain)
   (hackmode:domain-name domain)))

(defun register-subfinder-provider (&key (runner #'run-subfinder) (priority 20))
  "Register Subfinder as a typed SUBDOMAIN-ENUMERATE provider."
  (hackmode:register-capability-provider
   :subdomain-enumerate
   :subfinder
   (lambda (domain)
     (subfinder-enumerate domain :runner runner))
   :input-type 'hackmode:domain
   :output-types '(hackmode:domain)
   :priority priority))

(defun crtsh-name-values (json)
  (let ((objects (jsown:parse (or json "[]"))))
    (loop for object in objects
          for value = (jsown:val-safe object "name_value")
          when (stringp value)
            append (uiop:split-string value :separator '(#\Newline #\Return)))))

(defun parse-crtsh-response (json root-domain)
  "Parse crt.sh JSON into unique typed domains beneath ROOT-DOMAIN."
  (domain-assets-from-names
   (crtsh-name-values json)
   root-domain
   "crt.sh"
   '("dns" "crt.sh")))

(defun run-crtsh-json (domain)
  "Query crt.sh for typed DOMAIN and return the JSON response body."
  (check-type domain hackmode:domain)
  (dex:get
   (format nil "https://crt.sh/?q=%25.~a&output=json"
           (hackmode:domain-name domain))
   :headers '(("User-Agent" . "Hackmode")
              ("Accept" . "application/json"))))

(defun crtsh-enumerate (domain &key (runner #'run-crtsh-json))
  "Enumerate certificate-transparency names for typed DOMAIN through RUNNER."
  (check-type domain hackmode:domain)
  (parse-crtsh-response
   (funcall runner domain)
   (hackmode:domain-name domain)))

(defun register-crtsh-provider (&key (runner #'run-crtsh-json) (priority 40))
  "Register crt.sh as a typed SUBDOMAIN-ENUMERATE provider."
  (hackmode:register-capability-provider
   :subdomain-enumerate
   :crtsh
   (lambda (domain)
     (crtsh-enumerate domain :runner runner))
   :input-type 'hackmode:domain
   :output-types '(hackmode:domain)
   :priority priority))

(defun parse-http-probe-output (output)
  "Parse one tab-separated curl write-out record into a property list."
  (let* ((line (trim-text output))
         (parts (uiop:split-string line :separator '(#\Tab))))
    (unless (= 5 (length parts))
      (error "Invalid HTTP probe output: ~s" output))
    (list :status (parse-integer (first parts))
          :effective-url (second parts)
          :content-type (third parts)
          :remote-ip (fourth parts)
          :redirects (parse-integer (fifth parts)))))

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
             "--write-out"
             "%{http_code}\t%{url_effective}\t%{content_type}\t%{remote_ip}\t%{num_redirects}\n"
             (hackmode:asset-canonical-value url))
       :output :string
       :error-output :string
       :ignore-error-status t)
    (unless (or (null exit-code) (zerop exit-code))
      (error "HTTP probe exited with status ~a: ~a"
             exit-code
             (trim-text stderr)))
    (or stdout "")))

(defun http-observation-data (observation)
  (format nil
          "status=~d~%effective-url=~a~%content-type=~a~%remote-ip=~a~%redirects=~d"
          (getf observation :status)
          (getf observation :effective-url)
          (getf observation :content-type)
          (getf observation :remote-ip)
          (getf observation :redirects)))

(defun http-probe (url &key (runner #'run-http-probe))
  "Probe typed URL through RUNNER and return one typed HTTP observation finding."
  (check-type url hackmode:url)
  (hackmode:normalize-asset url)
  (let ((observation (parse-http-probe-output (funcall runner url))))
    (list
     (make-instance 'hackmode:finding
                    :document-id (hackmode:asset-deterministic-id url)
                    :finding-type "http-observation"
                    :data (http-observation-data observation)
                    :tool "curl"
                    :tags '("http" "probe")))))

(defun register-http-probe-provider (&key (runner #'run-http-probe) (priority 20))
  "Register the bounded HTTP probe as a typed HTTP-PROBE provider."
  (hackmode:register-capability-provider
   :http-probe
   :curl
   (lambda (url)
     (http-probe url :runner runner))
   :input-type 'hackmode:url
   :output-types '(hackmode:finding)
   :priority priority))

(defun register-recon-providers ()
  "Register the baseline concrete recon providers."
  (register-subfinder-provider)
  (register-crtsh-provider)
  (register-http-probe-provider)
  t)

(eval-when (:load-toplevel :execute)
  (register-recon-providers))
