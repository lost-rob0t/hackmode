(in-package :hackmode-starlang)

(defparameter *nuclei-program*
  (or (uiop:getenv "HACKMODE_NUCLEI_PROGRAM") "nuclei")
  "Nuclei executable used by the vuln-scan provider.")

(defun parse-nuclei-line (line)
  "Parse one Nuclei JSONL line into a plist that keeps the exact source line."
  (let ((object (jsown:parse line)))
    (list :template-id (jsown:val-safe object "template-id")
          :severity (string-downcase
                     (or (ignore-errors
                          (jsown:val (jsown:val-safe object "info") "severity"))
                         "unknown"))
          :host (jsown:val-safe object "host")
          :matched-at (jsown:val-safe object "matched-at")
          :line line)))

(defun parse-nuclei-output (output)
  "Parse Nuclei JSONL OUTPUT into plists preserving each exact source line."
  (loop for line in (uiop:split-string (or output "")
                                       :separator '(#\Newline #\Return))
        for trimmed = (string-trim '(#\Space #\Tab) line)
        unless (zerop (length trimmed))
          collect (parse-nuclei-line trimmed)))

(defun run-nuclei (target)
  "Run Nuclei against typed TARGET domain and return its raw JSONL stdout."
  (check-type target hackmode:domain)
  (hackmode:normalize-asset target)
  (multiple-value-bind (stdout stderr exit-code)
      (uiop:run-program
       (list *nuclei-program*
             "-silent"
             "-jsonl"
             "-target"
             (hackmode:domain-name target))
       :output :string
       :error-output :string
       :ignore-error-status t)
    (unless (or (null exit-code) (zerop exit-code))
      (error "Nuclei exited with status ~a: ~a"
             exit-code
             (string-trim '(#\Space #\Tab #\Newline #\Return) (or stderr ""))))
    (or stdout "")))

(defun nuclei-findings (target &key (runner #'run-nuclei))
  "Scan typed TARGET through RUNNER and return typed findings.

Each finding keeps the exact Nuclei output line as its data. Captured tool
evidence is preserved verbatim; projections may reference it but never
rewrite it."
  (check-type target hackmode:domain)
  (hackmode:normalize-asset target)
  (let ((target-id (hackmode:asset-deterministic-id target)))
    (loop for finding in (parse-nuclei-output (funcall runner target))
          collect (make-instance 'hackmode:finding
                                 :document-id target-id
                                 :finding-type "nuclei-finding"
                                 :data (getf finding :line)
                                 :tool "nuclei"
                                 :tags '("vuln" "nuclei")))))

(defun register-nuclei-provider (&key (runner #'run-nuclei) (priority 20))
  "Register Nuclei as a typed VULN-SCAN provider."
  (hackmode:register-capability-provider
   :vuln-scan
   :nuclei
   (lambda (target)
     (nuclei-findings target :runner runner))
   :input-type 'hackmode:domain
   :output-types '(hackmode:finding)
   :priority priority))

(defun register-pentest-providers (&key (nuclei-runner #'run-nuclei))
  "Register the Star-Lang-declared pentest providers available in this image.

Recon providers stay owned by their provider systems and are wired here by
delegation when those systems are loaded, so no provider backend is
duplicated. Returns the registered (capability provider) pairs."
  (let ((registered '()))
    (hackmode:unregister-capability-provider :vuln-scan :nuclei)
    (register-nuclei-provider :runner nuclei-runner)
    (push (list :vuln-scan "nuclei") registered)
    (when (find-package :hackmode-provider-recon)
      (let ((register (find-symbol "REGISTER-RECON-PROVIDERS"
                                   :hackmode-provider-recon)))
        (when (and register (fboundp register))
          (funcall register)
          (push (list :subdomain-enumerate "subfinder") registered)
          (push (list :subdomain-enumerate "crtsh") registered)
          (push (list :http-probe "curl") registered))))
    (nreverse registered)))
