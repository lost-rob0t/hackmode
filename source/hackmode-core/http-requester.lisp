(in-package :hackmode)

(define-condition http-request-policy-error (error)
  ((reason :initarg :reason :reader http-request-policy-error-reason))
  (:report (lambda (condition stream)
             (format stream "HTTP request policy rejected execution: ~a"
                     (http-request-policy-error-reason condition)))))

(defparameter *http-redirect-policies* '(:manual :same-origin :follow))

(defstruct (http-request (:constructor %make-http-request))
  operation-id
  run-id
  url
  (method :get)
  headers
  body
  redirect-policy
  timeout-seconds
  client-profile
  capture-mode)

(defun validate-http-request (request)
  (check-type request http-request)
  (unless (and (stringp (http-request-operation-id request))
               (plusp (length (http-request-operation-id request))))
    (error 'http-request-policy-error :reason "missing operation identity"))
  (unless (and (stringp (http-request-run-id request))
               (plusp (length (http-request-run-id request))))
    (error 'http-request-policy-error :reason "missing run identity"))
  (unless (and (stringp (http-request-url request))
               (plusp (length (http-request-url request))))
    (error 'http-request-policy-error :reason "missing request URL"))
  (unless (member (http-request-redirect-policy request)
                  *http-redirect-policies* :test #'eq)
    (error 'http-request-policy-error
           :reason (format nil "unknown redirect policy ~s"
                           (http-request-redirect-policy request))))
  (unless (and (realp (http-request-timeout-seconds request))
               (plusp (http-request-timeout-seconds request)))
    (error 'http-request-policy-error :reason "timeout must be positive"))
  (validate-http-client-profile (http-request-client-profile request))
  (normalize-capture-mode (http-request-capture-mode request))
  request)

(defun make-http-request (&key operation-id run-id url (method :get) headers body
                            redirect-policy timeout-seconds client-profile capture-mode)
  (validate-http-request
   (%make-http-request :operation-id operation-id
                       :run-id run-id
                       :url url
                       :method method
                       :headers (copy-tree headers)
                       :body body
                       :redirect-policy redirect-policy
                       :timeout-seconds timeout-seconds
                       :client-profile client-profile
                       :capture-mode capture-mode)))

(defun http-request-provenance (request &key backend-id backend-version)
  "Return execution provenance without request headers, body, URL credentials, or secrets."
  (validate-http-request request)
  (let ((profile (http-request-client-profile request)))
    (list :operation-id (http-request-operation-id request)
          :run-id (http-request-run-id request)
          :backend-id backend-id
          :backend-version backend-version
          :profile-id (http-client-profile-id profile)
          :profile-version (http-client-profile-version profile)
          :browser-family (http-client-profile-browser-family profile)
          :browser-version (http-client-profile-browser-version profile)
          :http-protocol (http-client-profile-http-protocol profile)
          :capture-mode (http-request-capture-mode request)
          :redirect-policy (http-request-redirect-policy request)
          :timeout-seconds (http-request-timeout-seconds request))))
