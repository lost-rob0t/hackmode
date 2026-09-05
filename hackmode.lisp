(declaim (optimize (speed 3) (safety 1)))

(defpackage :hackmode-user
  (:use :cl)
  (:export
   :main
   :expert-shell
   :scan-command
   :recon-command
   :inventory-import-command)
  (:documentation "Hackmode CLI and expert-shell entry points."))

(in-package :hackmode-user)

(defun trim-line (value)
  (string-trim '(#\Space #\Tab #\Newline #\Return) (or value "")))

(defun load-user-init ()
  "Load the Hackmode init file when it exists."
  (let ((path (pathname hackmode:hackmode-init-file)))
    (when (probe-file path)
      (load path))))

(defun initialize-runtime (&key interactive)
  "Initialize shared Hackmode runtime state for CLI or shell use."
  (setf hackmode::*interactive* interactive)
  (load-user-init)
  (nhooks:run-hook hackmode:*startup-hook*)
  (hackmode-provider-recon:register-recon-providers)
  (hackmode-provider-dns:register-massdns-provider)
  t)

(defun default-operation-name ()
  "Return a stable per-workspace operation name for one-shot CLI commands."
  (let* ((directory
           (namestring
            (uiop:ensure-directory-pathname (uiop:getcwd))))
         (digest (starintel:digest-id "hackmode-cli-operation" directory)))
    (format nil "cli-~a" (subseq digest 0 (min 16 (length digest))))))

(defun ensure-cli-operation ()
  "Select an operation for command-mode work, creating one for CWD if needed."
  (or (hackmode:current-operation)
      (let* ((directory
               (namestring
                (uiop:ensure-directory-pathname (uiop:getcwd))))
             (configured-name (uiop:getenv "HACKMODE_OPERATION"))
             (name
               (if (and configured-name (plusp (length configured-name)))
                   configured-name
                   (default-operation-name))))
        (unless (hackmode:select-operation name)
          (hackmode:new-operation
           name
           directory
           "Hackmode CLI operation"))
        (hackmode:use-operation name))))

(defun print-help (&optional (stream *standard-output*))
  (format stream
          "Hackmode~%~%
Usage:~%
  hm expert~%
  hm scan TARGET [NMAP-ARG ...]~%
  hm recon DOMAIN~%
  hm inventory import FILE [auto|domain|host|url]~%
~%
Environment:~%
  HACKMODE_OPERATION   operation name for command-mode persistence~%
~%
Nix entry points:~%
  nix run github:lost-rob0t/hackmode~%
  nix run github:lost-rob0t/hackmode#expert~%")
  0)

(defun persist-recon-assets (assets)
  (ensure-cli-operation)
  (loop for asset in assets
        do (hackmode:record-recon-asset asset)
        finally (return assets)))

(defun scan-command (target &optional nmap-arguments)
  "Run an Nmap XML scan against TARGET and persist the observation locally.

NMAP-ARGUMENTS are passed as separate argv values. Hackmode forces XML output to
stdout so the complete observation can be retained in the active operation."
  (when (zerop (length (trim-line target)))
    (error "SCAN requires a non-empty target."))
  (ensure-cli-operation)
  (multiple-value-bind (stdout stderr status)
      (uiop:run-program
       (append (list "nmap")
               nmap-arguments
               (list "-oX" "-" target))
       :output :string
       :error-output :string
       :ignore-error-status t)
    (when (plusp (length stdout))
      (write-string stdout *standard-output*)
      (finish-output *standard-output*))
    (when (plusp (length stderr))
      (write-string stderr *error-output*)
      (finish-output *error-output*))
    (when (or (null status) (zerop status))
      (hackmode:record-recon-asset
       (make-instance 'hackmode:finding
                      :document-id target
                      :finding-type "nmap-xml"
                      :data stdout
                      :tool "nmap"
                      :tags '("scan" "nmap" "xml"))))
    (if (null status) 0 status)))

(defun recon-command (domain-name)
  "Run baseline passive/domain recon and persist unique typed domain assets."
  (let* ((root
           (make-instance 'hackmode:domain
                          :record (trim-line domain-name)))
         (seen (make-hash-table :test #'equal))
         (assets nil)
         (successful-providers 0))
    (ensure-cli-operation)
    (labels ((collect-provider (name thunk)
               (handler-case
                   (let ((provider-assets (funcall thunk)))
                     (incf successful-providers)
                     (dolist (asset provider-assets)
                       (let ((key (hackmode:domain-name asset)))
                         (unless (gethash key seen)
                           (setf (gethash key seen) t)
                           (push asset assets)))))
                 (error (condition)
                   (format *error-output*
                           "~&recon provider ~a failed: ~a~%"
                           name
                           condition)))))
      (collect-provider
       "subfinder"
       (lambda ()
         (hackmode-provider-recon:subfinder-enumerate root)))
      (collect-provider
       "crt.sh"
       (lambda ()
         (hackmode-provider-recon:crtsh-enumerate root))))
    (setf assets (nreverse assets))
    (persist-recon-assets assets)
    (dolist (asset assets)
      (format t "~a~%" (hackmode:domain-name asset)))
    (format *error-output*
            "recon: ~d unique domain asset~:p persisted~%"
            (length assets))
    (if (plusp successful-providers) 0 1)))

(defun comment-or-empty-line-p (line)
  (or (zerop (length line))
      (char= (char line 0) #\#)))

(defun ipv4-literal-p (value)
  (not (null
        (cl-ppcre:scan
         "^([0-9]{1,3}\\.){3}[0-9]{1,3}$"
         value))))

(defun url-literal-p (value)
  (or (and (>= (length value) 7)
           (string-equal "http://" value :end2 7))
      (and (>= (length value) 8)
           (string-equal "https://" value :end2 8))))

(defun make-inventory-asset (line kind)
  (let* ((value (trim-line line))
         (normalized-kind (string-downcase (or kind "auto"))))
    (cond
      ((string= normalized-kind "domain")
       (make-instance 'hackmode:domain :record value))
      ((string= normalized-kind "host")
       (if (or (ipv4-literal-p value) (find #\: value))
           (make-instance 'hackmode:host :ip value)
           (make-instance 'hackmode:host :hostname value)))
      ((string= normalized-kind "url")
       (hackmode:parse-url value))
      ((string= normalized-kind "auto")
       (cond
         ((url-literal-p value)
          (hackmode:parse-url value))
         ((or (ipv4-literal-p value) (find #\: value))
          (make-instance 'hackmode:host :ip value))
         (t
          (make-instance 'hackmode:domain :record value))))
      (t
       (error "Unknown inventory type ~s; expected auto, domain, host, or url."
              kind)))))

(defun read-inventory-assets (path kind)
  "Parse PATH completely before any mutation of the operation store."
  (with-open-file (stream path :direction :input)
    (loop for raw = (read-line stream nil nil)
          while raw
          for line = (trim-line raw)
          unless (comment-or-empty-line-p line)
            collect (make-inventory-asset line kind))))

(defun inventory-import-command (path &optional (kind "auto"))
  "Import newline-delimited inventory from PATH into the active operation."
  (let ((assets (read-inventory-assets path kind)))
    (ensure-cli-operation)
    (persist-recon-assets assets)
    (format t "inventory: imported ~d asset~:p from ~a~%"
            (length assets)
            path)
    0))

(defun expert-shell ()
  "Start the interactive Hackmode expert shell backed by Lish."
  (initialize-runtime :interactive t)
  (shellpool:start)
  (setf *package* (find-package :cl-user))
  (use-package :hackmode :cl-user)
  (lish:lish)
  0)

(defun dispatch-command (arguments)
  (let ((command (first arguments))
        (rest (rest arguments)))
    (cond
      ((or (null command)
           (member command '("help" "--help" "-h") :test #'string=))
       (print-help))
      ((member command '("expert" "shell") :test #'string=)
       (expert-shell))
      ((string= command "scan")
       (unless rest
         (error "Usage: hm scan TARGET [NMAP-ARG ...]"))
       (initialize-runtime :interactive nil)
       (scan-command (first rest) (rest rest)))
      ((string= command "recon")
       (unless (= 1 (length rest))
         (error "Usage: hm recon DOMAIN"))
       (initialize-runtime :interactive nil)
       (recon-command (first rest)))
      ((string= command "inventory")
       (unless (and (>= (length rest) 2)
                    (string= (first rest) "import")
                    (<= (length rest) 3))
         (error "Usage: hm inventory import FILE [auto|domain|host|url]"))
       (initialize-runtime :interactive nil)
       (inventory-import-command
        (second rest)
        (or (third rest) "auto")))
      (t
       (format *error-output* "Unknown Hackmode command: ~a~%~%" command)
       (print-help *error-output*)
       2))))

;; Keep interactive Lish and the public CLI on exactly the same implementation
;; functions. These are intentionally thin adapters, not parallel command logic.
(lish:defcommand scan ((target string))
  "Run a baseline Nmap scan and persist its XML observation."
  (scan-command target))

(lish:defcommand recon ((domain string))
  "Run baseline domain reconnaissance and persist discovered domains."
  (recon-command domain))

(lish:defcommand inventory ((action string) (path string))
  "Inventory commands. Currently: inventory import FILE."
  (unless (string-equal action "import")
    (error "Usage: inventory import FILE"))
  (inventory-import-command path))

(defun main (&optional (arguments (uiop:command-line-arguments)))
  "Hackmode executable entry point."
  (handler-case
      (uiop:quit (dispatch-command arguments))
    (error (condition)
      (format *error-output* "hm: ~a~%" condition)
      (uiop:quit 1))))
