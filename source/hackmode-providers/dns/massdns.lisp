(in-package :hackmode-provider-dns)

(defparameter *massdns-program*
  (or (uiop:getenv "HACKMODE_MASSDNS_PROGRAM") "massdns")
  "MassDNS executable used by the DNS provider backend.")

(defparameter *massdns-resolvers*
  (or (uiop:getenv "HACKMODE_MASSDNS_RESOLVERS")
      (namestring
       (merge-pathnames "wordlists/resolvers/resolvers.txt"
                        (user-homedir-pathname))))
  "Resolver list used by MassDNS. Override with HACKMODE_MASSDNS_RESOLVERS.")

(defun massdns-answer-addresses (object record-type)
  (let* ((data (jsown:val-safe object "data"))
         (answers (and data (jsown:val-safe data "answers"))))
    (loop for answer in answers
          for answer-type = (jsown:val-safe answer "type")
          for value = (jsown:val-safe answer "data")
          when (and (stringp answer-type)
                    (string-equal answer-type record-type)
                    (stringp value)
                    (plusp (length value)))
            collect value)))

(defun parse-massdns-json-line (line)
  "Parse one MassDNS NDJSON LINE into a typed Hackmode domain or NIL.

This preserves the legacy dns-up.sh behavior of retaining only NOERROR names,
while also carrying matching A/AAAA answer data into DOMAIN-IPS."
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) line)))
    (when (plusp (length trimmed))
      (let* ((object (jsown:parse trimmed))
             (status (jsown:val-safe object "status"))
             (name (jsown:val-safe object "name"))
             (candidate-type (jsown:val-safe object "type"))
             (record-type (if (stringp candidate-type) candidate-type "A")))
        (when (and (stringp status)
                   (string-equal status "NOERROR")
                   (stringp name)
                   (plusp (length name)))
          (make-instance 'hackmode:domain
                         :record (string-right-trim '(#\.) name)
                         :record-type (string-upcase record-type)
                         :ips (massdns-answer-addresses object record-type)
                         :tool "massdns"
                         :tags '("dns" "massdns")))))))

(defun parse-massdns-output (output)
  "Parse MassDNS NDJSON OUTPUT into typed domain assets."
  (with-input-from-string (stream output)
    (loop for line = (read-line stream nil nil)
          while line
          for asset = (parse-massdns-json-line line)
          when asset collect asset)))

(defun fresh-massdns-input-path ()
  (merge-pathnames
   (format nil "hackmode-massdns-~36r-~36r.txt"
           (get-universal-time)
           (random most-positive-fixnum))
   (uiop:temporary-directory)))

(defun run-massdns-json (domain)
  "Run MassDNS for typed DOMAIN and return NDJSON stdout.

The provider invokes MassDNS with an argv list through UIOP rather than a shell
command string, so domain/config values are not reinterpreted as shell syntax."
  (check-type domain hackmode:domain)
  (unless (probe-file *massdns-resolvers*)
    (error "MassDNS resolver list does not exist: ~a" *massdns-resolvers*))
  (let* ((input-path (fresh-massdns-input-path))
         (record-type (let ((value (hackmode:domain-type domain)))
                        (if (plusp (length value)) value "A"))))
    (unwind-protect
         (progn
           (with-open-file (stream input-path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-line (hackmode:domain-name domain) stream))
           (multiple-value-bind (stdout stderr exit-code)
               (uiop:run-program
                (list *massdns-program*
                      "-r" *massdns-resolvers*
                      "-t" (string-upcase record-type)
                      "-o" "J"
                      (namestring input-path))
                :output :string
                :error-output :string
                :ignore-error-status t)
             (unless (zerop exit-code)
               (error "MassDNS exited with status ~d: ~a"
                      exit-code
                      (string-trim '(#\Space #\Tab #\Newline #\Return)
                                   (or stderr ""))))
             stdout))
      (when (probe-file input-path)
        (delete-file input-path)))))

(defun massdns-resolve (domain &key (runner #'run-massdns-json))
  "Resolve typed DOMAIN through RUNNER and return typed domain assets."
  (parse-massdns-output (funcall runner domain)))

(defun register-massdns-provider (&key (runner #'run-massdns-json) (priority 20))
  "Register MassDNS as the :DNS-RESOLVE backend and return its definition."
  (hackmode:register-capability-provider
   :dns-resolve
   :massdns
   (lambda (domain)
     (massdns-resolve domain :runner runner))
   :input-type 'hackmode:domain
   :output-types '(hackmode:domain)
   :priority priority))

(eval-when (:load-toplevel :execute)
  (register-massdns-provider))
