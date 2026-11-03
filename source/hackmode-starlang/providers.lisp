(in-package :hackmode-starlang)

(defparameter *nuclei-program*
  (or (uiop:getenv "HACKMODE_NUCLEI_PROGRAM") "nuclei")
  "Nuclei executable used by the vuln-scan provider.")

(defun parse-nuclei-line (line)
  "Parse one Nuclei JSONL line into a plist that keeps the exact raw line."
  (let ((object (jsown:parse line)))
    (list :template-id (jsown:val-safe object "template-id")
          :severity (or (ignore-errors
                          (string-downcase
                           (jsown:val (jsown:val-safe object "info") "severity")))
                         "unknown")
          :host (jsown:val-safe object "host")
          :matched-at (jsown:val-safe object "matched-at")
          :line line)))

(defun parse-nuclei-output (output)
  "Parse Nuclei JSONL OUTPUT into plists, preserving evidence losslessly.

A line that fails to parse becomes a (:parse-error t) plist carrying the
exact raw line instead of aborting the scan: one truncated or contaminated
line must never destroy the findings already captured around it."
  (loop for line in (uiop:split-string (or output "")
                                       :separator '(#\Newline #\Return))
        unless (zerop (length (string-trim '(#\Space #\Tab) line)))
          collect (handler-case
                      (parse-nuclei-line line)
                    (error ()
                      (list :parse-error t :line line)))))

(defun run-nuclei (target)
  "Run Nuclei against typed TARGET; return stdout, stderr, and exit code.

The caller decides how a nonzero exit is recorded. stdout is returned
complete even when the process exits nonzero after streaming findings, so
no captured output is discarded here."
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
    (values (or stdout "") (or stderr "") exit-code)))

(defun nuclei-findings (target &key (runner #'run-nuclei))
  "Scan typed TARGET through RUNNER and return typed findings.

Every stdout line survives: parsable matches become nuclei-finding assets
and unparsable lines become nuclei-parse-error findings carrying the exact
raw line, so partial or contaminated output is preserved verbatim instead
of silently dropped.

A nonzero exit surfaces as an error embedding the complete raw stdout and
stderr, which keeps them retrievable in the provider job's error record —
until tool-run documents (design doc slice 2) can record exit status,
stdout, and stderr losslessly alongside persisted findings."
  (check-type target hackmode:domain)
  (hackmode:normalize-asset target)
  (multiple-value-bind (stdout stderr exit-code)
      (funcall runner target)
    (unless (or (null exit-code) (zerop exit-code))
      (error "Nuclei exited with status ~a.~%stderr: ~a~%stdout: ~a"
             exit-code
             (string-trim '(#\Space #\Tab #\Newline #\Return) stderr)
             stdout))
    (let ((target-id (hackmode:asset-deterministic-id target)))
      (loop for finding in (parse-nuclei-output stdout)
            for parse-error-p = (getf finding :parse-error)
            collect (make-instance 'hackmode:finding
                                   :document-id target-id
                                   :finding-type (if parse-error-p
                                                     "nuclei-parse-error"
                                                     "nuclei-finding")
                                   :data (getf finding :line)
                                   :tool "nuclei"
                                   :tags (if parse-error-p
                                             '("vuln" "nuclei" "parse-error")
                                             '("vuln" "nuclei")))))))

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

Re-registering resets the registered providers to their default runners
(registration overwrites by capability/provider key). Recon backends stay
owned by their provider systems: when hackmode-provider-recon is loaded,
its registrations are refreshed here by delegation so no provider backend
is duplicated; hackmode-provider-dns self-registers at load and is not
re-wired. Returns the registered (capability provider) pairs."
  (let ((registered '()))
    (register-nuclei-provider :runner nuclei-runner)
    (push (list :vuln-scan "nuclei") registered)
    (cond
      ((null (find-package :hackmode-provider-recon))
       ;; Optional system absent: whatever recon registrations exist stay
       ;; untouched.
       )
      (t
       (let ((register (find-symbol "REGISTER-RECON-PROVIDERS"
                                    :hackmode-provider-recon)))
         (cond
           ((and register (fboundp register))
            (funcall register)
            (push (list :subdomain-enumerate "subfinder") registered)
            (push (list :subdomain-enumerate "crtsh") registered)
            (push (list :http-probe "curl") registered))
           (t
            (warn "hackmode-provider-recon is loaded but \
REGISTER-RECON-PROVIDERS is missing; recon providers were not refreshed."))))))
    (nreverse registered)))
