(in-package :hackmode-database)

(defconstant +http-exchange-max-header-count+ 64)
(defconstant +http-exchange-max-header-name-length+ 128)
(defconstant +http-exchange-max-header-value-length+ 4096)

(defparameter +http-exchange-sensitive-header-names+
  '("authorization"
    "proxy-authorization"
    "cookie"
    "set-cookie"
    "x-api-key"
    "x-auth-token"
    "api-key"))

(defun %proper-list-p (value)
  (or (null value)
      (ignore-errors (integerp (list-length value)))))

(defun %sensitive-http-header-name-p (name)
  (member name +http-exchange-sensitive-header-names+
          :test #'string-equal))

(defun %sanitize-http-headers (field headers)
  (unless (%proper-list-p headers)
    (error 'execution-graph-validation-error
           :field field :value headers
           :reason "expected a proper list of HTTP header pairs"))
  (when (> (length headers) +http-exchange-max-header-count+)
    (error 'execution-graph-validation-error
           :field field :value headers
           :reason "too many HTTP headers"))
  (loop for entry in headers
        collect
        (progn
          (unless (and (consp entry)
                       (stringp (car entry))
                       (stringp (cdr entry)))
            (error 'execution-graph-validation-error
                   :field field :value entry
                   :reason "expected (header-name . header-value) string pair"))
          (let ((name (car entry))
                (value (cdr entry)))
            (unless (%non-empty-string-p name)
              (error 'execution-graph-validation-error
                     :field field :value entry
                     :reason "HTTP header name must be non-empty"))
            (when (> (length name) +http-exchange-max-header-name-length+)
              (error 'execution-graph-validation-error
                     :field field :value name
                     :reason "HTTP header name exceeds canonical bound"))
            (when (> (length value) +http-exchange-max-header-value-length+)
              (error 'execution-graph-validation-error
                     :field field :value name
                     :reason "HTTP header value exceeds canonical bound"))
            (when (%sensitive-http-header-name-p name)
              (error 'execution-graph-validation-error
                     :field field :value name
                     :reason "secret-bearing HTTP header is not canonical graph evidence"))
            (cons (copy-seq name) (copy-seq value))))))

(defun %validate-http-exchange-payload (payload)
  (unless (listp payload)
    (error 'execution-graph-validation-error
           :field :payload :value payload
           :reason "expected HTTP exchange property list"))
  (%require-string :method (getf payload :method))
  (let ((scheme (getf payload :scheme)))
    (%require-string :scheme scheme)
    (unless (member scheme '("http" "https") :test #'string-equal)
      (error 'execution-graph-validation-error
             :field :scheme :value scheme
             :reason "expected http or https scheme")))
  (%require-string :host (getf payload :host))
  (%require-http-port (getf payload :port))
  (%require-string :path (getf payload :path))
  (%require-http-status (getf payload :response-status))
  (%sanitize-http-headers :request-headers (getf payload :request-headers))
  (%sanitize-http-headers :response-headers (getf payload :response-headers))
  (%require-optional-string :request-body-digest (getf payload :request-body-digest))
  (%require-optional-string :response-body-digest (getf payload :response-body-digest))
  (%require-string :raw-evidence-ref (getf payload :raw-evidence-ref))
  (%require-string :observed-at (getf payload :observed-at))
  (%require-duration-ms (getf payload :duration-ms))
  payload)

(defun make-http-exchange-record
    (&key operation-id capture-session-id exchange-id method scheme host port path
          response-status request-headers response-headers request-body-digest
          response-body-digest raw-evidence-ref observed-at duration-ms provenance)
  "Construct one immutable, sanitized HTTP exchange evidence record."
  (%require-string :operation-id operation-id)
  (%require-string :capture-session-id capture-session-id)
  (%require-string :exchange-id exchange-id)
  (%require-provenance provenance)
  (let ((payload (list :method method
                       :scheme scheme
                       :host host
                       :port port
                       :path path
                       :response-status response-status
                       :request-headers
                       (%sanitize-http-headers :request-headers request-headers)
                       :response-headers
                       (%sanitize-http-headers :response-headers response-headers)
                       :request-body-digest request-body-digest
                       :response-body-digest response-body-digest
                       :raw-evidence-ref raw-evidence-ref
                       :observed-at observed-at
                       :duration-ms duration-ms)))
    (%validate-http-exchange-payload payload)
    (%make-execution-record
     :kind :http-exchange
     :operation-id operation-id
     :run-id capture-session-id
     :call-id exchange-id
     :record-id (%record-id "http-exchange"
                            operation-id capture-session-id exchange-id)
     :payload payload
     :provenance provenance)))
