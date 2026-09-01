(defpackage :hackmode-http-requester-tests
  (:use :cl))

(in-package :hackmode-http-requester-tests)

(defun check (condition format-control &rest format-arguments)
  (unless condition
    (error (apply #'format nil format-control format-arguments))))

(defun run-http-requester-tests ()
  (let* ((profile
           (hackmode::make-http-client-profile
            :id "chrome-stable"
            :version "1"
            :browser-family :chrome
            :browser-version "146"
            :user-agent "Mozilla/5.0 Chrome/146.0"
            :http-protocol :http2
            :backend :impersonating
            :capture-mode :tunnel))
         (request
           (hackmode::make-http-request
            :operation-id "op-http"
            :run-id "run-http"
            :url "https://example.invalid/path"
            :method :get
            :headers '(("Accept" . "text/html")
                       ("Authorization" . "secret-must-not-persist"))
            :redirect-policy :manual
            :timeout-seconds 5
            :client-profile profile
            :capture-mode :tunnel)))
    (hackmode::validate-http-request request)
    (check (string= "op-http" (hackmode::http-request-operation-id request))
           "Typed HTTP request must retain operation identity.")
    (check (eq :manual (hackmode::http-request-redirect-policy request))
           "Redirect policy must remain explicit.")
    (let ((provenance (hackmode::http-request-provenance request
                                                        :backend-id "curl-cffi"
                                                        :backend-version "0.16.2")))
      (check (string= "curl-cffi" (getf provenance :backend-id))
             "Execution provenance must identify the selected backend.")
      (check (string= "chrome-stable" (getf provenance :profile-id))
             "Execution provenance must identify the selected client profile.")
      (check (eq :tunnel (getf provenance :capture-mode))
             "Execution provenance must identify actual capture mode.")
      (check (null (search "secret-must-not-persist"
                           (prin1-to-string provenance)))
             "Request secrets must not enter execution provenance."))
    (handler-case
        (progn
          (hackmode::make-http-request
           :operation-id "op-http"
           :run-id "run-http"
           :url "https://example.invalid/"
           :method :get
           :redirect-policy :surprise-me
           :timeout-seconds 5
           :client-profile profile
           :capture-mode :direct)
          (error "Unknown redirect policy unexpectedly constructed."))
      (hackmode::http-request-policy-error () t))
    (handler-case
        (progn
          (hackmode::make-http-request
           :operation-id "op-http"
           :run-id "run-http"
           :url "https://example.invalid/"
           :method :get
           :redirect-policy :manual
           :timeout-seconds 0
           :client-profile profile
           :capture-mode :direct)
          (error "Non-positive timeout unexpectedly constructed."))
      (hackmode::http-request-policy-error () t))
    t))
