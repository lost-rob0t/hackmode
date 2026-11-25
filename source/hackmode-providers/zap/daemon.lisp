(in-package :hackmode-provider-zap)

;;;; ZAP daemon REST client.
;;;;
;;;; Talks ONLY to the operator's local ZAP daemon (loopback by default) with
;;;; the API key. Calls go through a curl subprocess with an argv list — no
;;;; shell interpolation. Every failure surfaces with the complete response
;;;; body so no captured evidence is lost, matching the recon provider's
;;;; subprocess style.

(defparameter *zap-url* (or (uiop:getenv "HACKMODE_ZAP_URL") "http://127.0.0.1:8090")
  "Base URL of the ZAP daemon REST API.")

(defparameter *zap-api-key-file* "/tmp/opencode/zap-api-key"
  "Fallback location of the daemon API key when HACKMODE_ZAP_API_KEY is unset.")

(defun zap-url ()
  "The daemon base URL, without a trailing slash."
  (string-right-trim "/" *zap-url*))

(defun zap-api-key ()
  "Resolve the API key: HACKMODE_ZAP_API_KEY env, else the key file."
  (let ((env (uiop:getenv "HACKMODE_ZAP_API_KEY")))
    (if (and env (plusp (length env)))
        env
        (let ((contents (and (probe-file *zap-api-key-file*)
                             (uiop:read-file-string *zap-api-key-file*))))
          (when contents
            (string-trim '(#\Space #\Tab #\Newline #\Return) contents))))))

(define-condition zap-error (error)
  ((message :initarg :message :reader zap-error-message)
   (body :initarg :body :initform nil :reader zap-error-body)
   (stderr :initarg :stderr :initform nil :reader zap-error-stderr))
  (:report (lambda (condition stream)
             (format stream "~a" (zap-error-message condition))
             (when (zap-error-stderr condition)
               (format stream "~%curl stderr: ~a" (zap-error-stderr condition)))
             (when (zap-error-body condition)
               (format stream "~%body: ~a" (zap-error-body condition))))))

(defun percent-encode (value)
  "Percent-encode VALUE for a query parameter. Unreserved RFC 3986 characters
pass through; everything else is byte-encoded so daemon-side decoding sees
the exact value."
  (with-output-to-string (stream)
    (loop for byte across (sb-ext:string-to-octets (princ-to-string value)
                                                   :external-format :utf-8)
          do (let ((char (code-char byte)))
               (if (or (char<= #\a char #\z)
                       (char<= #\A char #\Z)
                       (char<= #\0 char #\9)
                       (find char "-._~"))
                   (write-char char stream)
                   (format stream "%~2,'0x" byte))))))

(defun zap-request-argv (path-and-query)
  "Build the curl argv for one daemon GET."
  (list "curl" "--silent" "--show-error" "--max-time" "600"
        "-H" (format nil "X-ZAP-API-Key: ~a" (zap-api-key))
        (concatenate 'string (zap-url) path-and-query)))

(defun zap-get (path-and-query)
  "GET one JSON payload from the daemon; return the parsed jsown object.

Curl transport failures and daemon API errors ({\"code\": ...}) both raise
ZAP-ERROR carrying the complete response text, so nothing observed is
discarded on the way to an error record."
  (multiple-value-bind (stdout stderr exit-code)
      (uiop:run-program (zap-request-argv path-and-query)
                        :output :string
                        :error-output :string
                        :ignore-error-status t)
    (unless (zerop exit-code)
      (error 'zap-error
             :message (format nil "ZAP daemon curl exited with status ~a for ~a."
                              exit-code path-and-query)
             :stderr (or stderr "")))
    (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) (or stdout ""))))
      (unless (plusp (length trimmed))
        (error 'zap-error
               :message (format nil "ZAP daemon returned an empty response for ~a."
                                path-and-query)))
      (let ((object (jsown:parse trimmed)))
        (when (and (jsown:keyp object "code"))
          (error 'zap-error
                 :message (format nil "ZAP daemon API error for ~a: ~a ~a."
                                  path-and-query
                                  (jsown:val object "code")
                                  (if (jsown:keyp object "message")
                                      (jsown:val object "message")
                                      ""))
                 :body trimmed))
        object))))

(defun query-string (plist)
  "Encode a PLIST of (\"key\" value ...) pairs into a query string."
  (with-output-to-string (stream)
    (let ((firstp t))
      (loop for (key value) on plist by #'cddr
            do (progn
                 (unless firstp (write-char #\& stream))
                 (setf firstp nil)
                 (format stream "~a=~a" (percent-encode key) (percent-encode value)))))))

(defun zap-call (component kind name &rest plist)
  "Call /JSON/<component>/<kind>/<name>/ with PLIST query parameters.
Keys are strings, values are percent-encoded verbatim."
  (zap-get
   (if plist
       (format nil "/JSON/~a/~a/~a/?~a" component kind name (query-string plist))
       (format nil "/JSON/~a/~a/~a/" component kind name))))
