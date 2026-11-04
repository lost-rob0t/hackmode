;;;; Read-side StarIntel Server client.
;;;
;;; GET-only client for document fetch, FTS search, and health probing with an
;;; injectable request function so tests run without network I/O. Callers get
;;; keyword results, never raw transport conditions.
(in-package :hackmode)

(define-condition starintel-request-error (error)
  ((message :initarg :message :reader starintel-request-error-message))
  (:report (lambda (condition stream)
              (format stream "StarIntel request failed: ~a"
                      (starintel-request-error-message condition))))
  (:documentation "Transport-level failure reaching StarIntel Server."))

(defclass starintel-client ()
  ((config :initarg :config :reader starintel-client-config :type starintel-config)
   (request-fn :initarg :request-fn :reader starintel-client-request-fn :type function))
  (:default-initargs
   :config (or *starintel-config* (reload-starintel-config))
   :request-fn #'default-starintel-request)
  (:documentation "StarIntel Server read client with an injectable transport.

REQUEST-FN is called as (FUNCALL REQUEST-FN URL :HEADERS h :CONNECT-TIMEOUT c
:READ-TIMEOUT r) and returns BODY and HTTP STATUS as two values. The default
uses Dexador; tests inject fakes with the same contract."))

(defun default-starintel-request (url &key headers (connect-timeout 5) (read-timeout 10))
  "Perform a GET with Dexador and return BODY and STATUS.

Network failures raise STARINTEL-REQUEST-ERROR; HTTP error statuses come back
as ordinary values so callers decide how to map them."
  (handler-case
      (multiple-value-bind (body status)
          (dex:get url
                   :headers headers
                   :connect-timeout connect-timeout
                   :read-timeout read-timeout)
        (values body status))
    (dex:http-request-failed (condition)
      (values (dex:response-body condition)
              (dex:response-status condition)))
    (error (condition)
      (error 'starintel-request-error
             :message (format nil "~a" condition)))))

(defun starintel-client-url (client path &key query-params)
  "Build the absolute URL for PATH, percent-encoding QUERY-PARAMS."
  (let ((root (starintel-trailing-slash-trimmed
               (starintel-config-base-url (starintel-client-config client)))))
    (with-output-to-string (out)
      (format out "~a~a" root path)
      (when query-params
        (format out "?")
        (loop for ((name . value) . rest) on query-params
              do (format out "~a=~a" (quri:url-encode name) (quri:url-encode value))
              when rest do (format out "&"))))))

(defun starintel-client-request (client path &key query-params)
  "Issue one GET through CLIENT's request function.

Returns BODY and an integer HTTP status, or the body string and the symbol
:UNREACHABLE when the transport could not complete the request."
  (let* ((config (starintel-client-config client))
         (url (starintel-client-url client path :query-params query-params))
         (headers (append '(("Accept" . "application/json"))
                          (starintel-auth-headers config))))
    (handler-case
        (funcall (starintel-client-request-fn client) url
                 :headers headers
                 :connect-timeout (starintel-config-connect-timeout config)
                 :read-timeout (starintel-config-read-timeout config))
      (starintel-request-error (condition)
        (values (starintel-request-error-message condition) :unreachable))
      (error (condition)
        (values (format nil "~a" condition) :unreachable)))))

(defun starintel-status-keyword (status)
  "Map a non-success HTTP STATUS to the client's keyword result space."
  (case status
    (:unreachable :unreachable)
    (404 :not-found)
    ((401 403) :unauthorized)
    (t (if (and (integerp status) (<= 500 status 599))
           :server-error
           :client-error))))

(defun starintel-parse-json-body (body)
  "Parse BODY as JSON, or return :BAD-RESPONSE for malformed payloads.

JSOWN:PARSE returns NIL instead of signalling for some malformed inputs
in the wild, so NIL is treated as a bad response rather than a value."
  (handler-case
      (let ((parsed (jsown:parse body)))
        (if parsed parsed :bad-response))
    (error () :bad-response)))

(defun make-starintel-client (&key config (request-fn #'default-starintel-request))
  "Construct a STARINTEL-CLIENT for CONFIG (default: current configuration)."
  (make-instance 'starintel-client
                 :config (or config (current-starintel-config))
                 :request-fn request-fn))

(defun starintel-get-document (client id)
  "Fetch document ID through CLIENT.

Returns the parsed jsown object on success, or one of :NOT-FOUND,
:UNAUTHORIZED, :SERVER-ERROR, :CLIENT-ERROR, :BAD-RESPONSE, :UNREACHABLE."
  (multiple-value-bind (body status)
      (starintel-client-request client (format nil "/document/~a" id))
    (cond
      ((and (integerp status) (<= 200 status 299))
       (starintel-parse-json-body body))
      (t (starintel-status-keyword status)))))

(defun starintel-search (client query &key limit bookmark)
  "Search StarIntel Server FTS for QUERY.

Returns two values: a list of parsed document objects and the opaque bookmark
string for the next page (NIL when exhausted). On failure the first value is
one of the client keyword results and the second is NIL."
  (multiple-value-bind (body status)
      (starintel-client-request
       client "/search"
       :query-params (nconc
                      (list (cons "q" query))
                      (when limit
                        (list (cons "limit" (princ-to-string limit))))
                      (when (and bookmark (plusp (length bookmark)))
                        (list (cons "bookmark" bookmark)))))
    (cond
      ((and (integerp status) (<= 200 status 299))
       (handler-case
           (let* ((envelope (jsown:parse body))
                  (rows (jsown:val-safe envelope "rows"))
                  (docs (loop for row in rows
                              for doc = (jsown:val-safe row "doc")
                              collect (if (eq doc :null) row doc)))
                  (next (jsown:val-safe envelope "bookmark")))
             (values (coerce docs 'list)
                     (and (stringp next) (plusp (length next)) next)))
         (error () (values :bad-response nil))))
      (t (values (starintel-status-keyword status) nil)))))

(defun starintel-health-p (client)
  "Return true when StarIntel Server answers GET /health with 2xx."
  (multiple-value-bind (body status)
      (starintel-client-request client "/health")
    (declare (ignore body))
    (and (integerp status) (<= 200 status 299))))
