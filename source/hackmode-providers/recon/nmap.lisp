(in-package :hackmode-provider-recon)

(defparameter *nmap-program*
  (or (uiop:getenv "HACKMODE_NMAP_PROGRAM") "nmap")
  "Nmap executable used by the bounded service-enumeration provider.")

(defun nmap-target-value (host)
  (check-type host hackmode:host)
  (let ((ip (hackmode:doc-ip host))
        (hostname (hackmode:doc-host host)))
    (cond
      ((plusp (length ip)) ip)
      ((plusp (length hostname)) hostname)
      (t (error "Nmap host target has neither IP nor hostname.")))))

(defun run-nmap-service-xml (host)
  "Run bounded Nmap service/version detection for typed HOST and return XML.

The provider intentionally performs service fingerprinting only: no NSE script
execution, OS exploitation, credential use, or destructive probes are enabled."
  (let ((target (nmap-target-value host)))
    (multiple-value-bind (stdout stderr exit-code)
        (uiop:run-program
         (list *nmap-program*
               "-Pn"
               "-sV"
               "--version-light"
               "--host-timeout"
               "120s"
               "-oX"
               "-"
               target)
         :output :string
         :error-output :string
         :ignore-error-status t)
      (unless (or (null exit-code) (zerop exit-code))
        (error "Nmap exited with status ~a: ~a" exit-code (trim-text stderr)))
      (or stdout ""))))

(defun xml-attribute (text name)
  (multiple-value-bind (matched groups)
      (cl-ppcre:scan-to-strings
       (format nil "~a=\\\"([^\\\"]*)\\\"" name)
       text)
    (declare (ignore matched))
    (and groups (plusp (length groups)) (aref groups 0))))

(defun first-xml-text (text element)
  (multiple-value-bind (matched groups)
      (cl-ppcre:scan-to-strings
       (format nil "(?s)<~a[^>]*>([^<]*)</~a>" element element)
       text)
    (declare (ignore matched))
    (and groups (plusp (length groups)) (trim-text (aref groups 0)))))

(defun nmap-service-observation (protocol port-id body host)
  (let* ((service-tag
           (first (cl-ppcre:all-matches-as-strings "<service\\b[^>]*>" body)))
         (service-self
           (first (cl-ppcre:all-matches-as-strings "<service\\b[^>]*/>" body)))
         (service (or service-tag service-self ""))
         (name (or (xml-attribute service "name") ""))
         (product (or (xml-attribute service "product") ""))
         (version (or (xml-attribute service "version") ""))
         (cpe (or (first-xml-text body "cpe") ""))
         (data (jsown:new-js
                 ("port" (parse-integer port-id))
                 ("protocol" protocol)
                 ("name" name)
                 ("product" product)
                 ("version" version)
                 ("cpe" cpe))))
    (make-instance
     'hackmode:finding
     :document-id (hackmode:asset-deterministic-id host)
     :finding-type "service-observation"
     :data (jsown:to-json data)
     :operation (hackmode:doc-operation host)
     :tool "nmap"
     :tags '("service" "nmap" "fingerprint"))))

(defun parse-nmap-service-xml (xml host)
  "Parse open service observations from Nmap XML into typed findings."
  (let (findings)
    (cl-ppcre:do-register-groups (protocol port-id body)
        ("(?s)<port\\s+protocol=\"([^\"]+)\"\\s+portid=\"([0-9]+)\"[^>]*>(.*?)</port>"
         xml)
      (when (cl-ppcre:scan "<state\\s+state=\"open\"" body)
        (push (nmap-service-observation protocol port-id body host) findings)))
    (nreverse findings)))

(defun nmap-service-enumerate (host &key (runner #'run-nmap-service-xml))
  "Enumerate open services for typed HOST through RUNNER."
  (check-type host hackmode:host)
  (hackmode:normalize-asset host)
  (parse-nmap-service-xml (funcall runner host) host))

(defun register-nmap-provider (&key (runner #'run-nmap-service-xml) (priority 20))
  "Register Nmap as the typed SERVICE-ENUMERATE provider."
  (hackmode:register-capability-provider
   :service-enumerate
   :nmap
   (lambda (host)
     (nmap-service-enumerate host :runner runner))
   :input-type 'hackmode:host
   :output-types '(hackmode:finding)
   :priority priority))
