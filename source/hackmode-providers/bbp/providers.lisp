(in-package :hackmode-provider-bbp)

(defparameter *httpx-program*
  (or (uiop:getenv "HACKMODE_HTTPX_PROGRAM") "httpx")
  "ProjectDiscovery httpx executable used by the BBP HTTP provider.")

(defparameter *katana-program*
  (or (uiop:getenv "HACKMODE_KATANA_PROGRAM") "katana")
  "ProjectDiscovery Katana executable used by the BBP crawl provider.")

(defparameter *nmap-program*
  (or (uiop:getenv "HACKMODE_NMAP_PROGRAM") "nmap")
  "Nmap executable used by the BBP service-enumeration provider.")

(defun trim-text (value)
  (string-trim '(#\Space #\Tab #\Newline #\Return) (or value "")))

(defun run-program-output (argv)
  "Run ARGV without a shell and return stdout or signal a bounded tool failure."
  (multiple-value-bind (stdout stderr exit-code)
      (uiop:run-program argv
                        :output :string
                        :error-output :string
                        :ignore-error-status t
                        :force-shell nil)
    (unless (or (null exit-code) (zerop exit-code))
      (error "~a exited with status ~a: ~a"
             (first argv) exit-code (trim-text stderr)))
    (or stdout "")))

(defun output-lines (output)
  (remove-if
   (lambda (line) (zerop (length (trim-text line))))
   (uiop:split-string (or output "") :separator '(#\Newline #\Return))))

(defun json-url-asset (line tool &rest keys)
  (handler-case
      (let* ((object (jsown:parse line))
             (value
               (loop for key in keys
                     for candidate = (jsown:val-safe object key)
                     when (and (stringp candidate) (plusp (length candidate)))
                       return candidate)))
        (when value
          (let ((asset (hackmode:parse-url value)))
            (setf (hackmode:doc-tool asset) tool
                  (hackmode:doc-tags asset) (list "url" tool))
            asset)))
    (error () nil)))

(defun parse-httpx-output (output)
  "Parse httpx JSONL OUTPUT into deterministic Hackmode URL assets."
  (remove nil
          (mapcar (lambda (line)
                    (json-url-asset line "httpx" "url"))
                  (output-lines output))))

(defun parse-katana-output (output)
  "Parse Katana JSONL OUTPUT into deterministic Hackmode URL assets."
  (remove nil
          (mapcar (lambda (line)
                    (json-url-asset line "katana" "url" "endpoint"))
                  (output-lines output))))

(defun run-httpx (url)
  "Run httpx for one typed URL and return raw JSONL."
  (check-type url hackmode:url)
  (hackmode:normalize-asset url)
  (run-program-output
   (list *httpx-program*
         "-silent" "-json"
         "-u" (hackmode:asset-canonical-value url))))

(defun run-katana (url)
  "Run Katana for one typed URL and return raw JSONL."
  (check-type url hackmode:url)
  (hackmode:normalize-asset url)
  (run-program-output
   (list *katana-program*
         "-silent" "-jsonl"
         "-u" (hackmode:asset-canonical-value url))))

(defun httpx-probe (url &key (runner #'run-httpx))
  (parse-httpx-output (funcall runner url)))

(defun katana-crawl (url &key (runner #'run-katana))
  (parse-katana-output (funcall runner url)))

(defun parse-nmap-service (line)
  (multiple-value-bind (match groups)
      (cl-ppcre:scan-to-strings
       "^(\\d+)/(tcp|udp)\\s+(\\w+)\\s+(\\S+)(?:\\s+(.+?))?$"
       line)
    (declare (ignore match))
    (when (and groups (string= "open" (aref groups 2)))
      (list :port (parse-integer (aref groups 0))
            :protocol (aref groups 1)
            :name (aref groups 3)
            :version (or (aref groups 4) "")))))

(defun make-nmap-host (hostname ip services)
  (make-instance 'hackmode:host
                 :hostname hostname
                 :ip ip
                 :services services
                 :tool "nmap"
                 :tags '("host" "nmap")))

(defun parse-nmap-output (output)
  "Parse Nmap normal output into typed hosts carrying open service metadata."
  (let (assets current-host current-ip services)
    (labels ((flush ()
               (when current-host
                 (push (make-nmap-host current-host current-ip (nreverse services))
                       assets))
               (setf current-host nil
                     current-ip nil
                     services nil)))
      (dolist (line (output-lines output))
        (multiple-value-bind (match groups)
            (cl-ppcre:scan-to-strings
             "^Nmap scan report for (.+?)(?:\\s+\\((.+?)\\))?$"
             line)
          (if groups
              (progn
                (flush)
                (setf current-host (aref groups 0)
                      current-ip (or (aref groups 1) (aref groups 0))))
              (let ((service (parse-nmap-service line)))
                (when (and service current-host)
                  (push service services))))))
      (flush))
    (nreverse assets)))

(defun run-nmap (host)
  "Run Nmap service detection for one typed host and return normal output."
  (check-type host hackmode:host)
  (hackmode:normalize-asset host)
  (let ((target (if (plusp (length (hackmode:doc-ip host)))
                    (hackmode:doc-ip host)
                    (hackmode:doc-host host))))
    (run-program-output (list *nmap-program* "-sV" target))))

(defun nmap-enumerate (host &key (runner #'run-nmap))
  (parse-nmap-output (funcall runner host)))

(defun register-httpx-provider (&key (runner #'run-httpx) (priority 15))
  (hackmode:register-capability-provider
   :http-probe :httpx
   (lambda (url) (httpx-probe url :runner runner))
   :input-type 'hackmode:url
   :output-types '(hackmode:url)
   :priority priority))

(defun register-katana-provider (&key (runner #'run-katana) (priority 20))
  (hackmode:register-capability-provider
   :web-crawl :katana
   (lambda (url) (katana-crawl url :runner runner))
   :input-type 'hackmode:url
   :output-types '(hackmode:url)
   :priority priority))

(defun register-nmap-provider (&key (runner #'run-nmap) (priority 20))
  (hackmode:register-capability-provider
   :service-enumerate :nmap
   (lambda (host) (nmap-enumerate host :runner runner))
   :input-type 'hackmode:host
   :output-types '(hackmode:host)
   :priority priority))

(defun register-bbp-providers ()
  "Register the tool providers required by the BBP actor service."
  (hackmode-provider-recon:register-subfinder-provider)
  (hackmode-provider-dns:register-massdns-provider)
  (register-httpx-provider)
  (register-katana-provider)
  (register-nmap-provider)
  t)

(eval-when (:load-toplevel :execute)
  (register-bbp-providers))
