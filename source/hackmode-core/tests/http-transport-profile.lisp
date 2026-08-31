(defpackage :hackmode-http-transport-profile-tests
  (:use :cl))

(in-package :hackmode-http-transport-profile-tests)

(defun check (condition format-control &rest format-arguments)
  (unless condition
    (error (apply #'format nil format-control format-arguments))))

(defun run-http-transport-profile-tests ()
  (let* ((profile-a
           (hackmode::make-http-client-profile
            :id "firefox-linux"
            :version "1"
            :browser-family :firefox
            :browser-version "142"
            :user-agent "Mozilla/5.0 Firefox/142.0"
            :accept "text/html,application/xhtml+xml"
            :accept-language "en-US,en;q=0.5"
            :accept-encoding "gzip, deflate, br"
            :fetch-headers '(("Sec-Fetch-Site" . "none")
                             ("Authorization" . "secret-must-not-persist"))
            :client-hints '(("Sec-CH-UA-Mobile" . "?0"))
            :http-protocol :http2
            :backend :browser
            :capture-mode :intercept))
         (profile-z
           (hackmode::make-http-client-profile
            :id "z-profile"
            :version "1"
            :browser-family :firefox
            :browser-version "142"
            :user-agent "Mozilla/5.0 Firefox/142.0"
            :http-protocol :http2
            :backend :browser
            :capture-mode :direct))
         (profile-b
           (hackmode::select-http-client-profile
            (list profile-a)
            :profile-id "firefox-linux"))
         (http-support
           (hackmode::make-provider-transport-support
            :http-proxy-p t
            :https-proxy-p t
            :capture-modes '(:intercept :tunnel :direct)))
         (dns-support
           (hackmode::make-provider-transport-support
            :direct-only-p t
            :capture-modes '(:unsupported))))
    (check (eq profile-a profile-b)
           "Explicit profile selection must be deterministic.")
    (check (eq profile-a
               (hackmode::select-http-client-profile
                (list profile-z profile-a)))
           "Default profile selection must not depend on registry ordering.")
    (check (hackmode::http-client-profile-coherent-p profile-a)
           "Fixture browser profile must be coherent.")
    (check (eq :intercept
               (hackmode::resolve-provider-capture-mode
                http-support :intercept :capture-required-p t))
           "HTTP provider must accept supported required capture mode.")
    (handler-case
        (progn
          (hackmode::resolve-provider-capture-mode
           dns-support :intercept :capture-required-p t)
          (error "Required capture unexpectedly downgraded for direct-only provider."))
      (hackmode::provider-transport-policy-error () t))
    (check (eq :unsupported
               (hackmode::resolve-provider-capture-mode
                dns-support :unsupported :capture-required-p nil))
           "Protocol-inapplicable provider must remain explicitly unsupported.")
    (let* ((snapshot (hackmode::http-client-profile-provenance profile-a))
           (headers (getf snapshot :fetch-headers)))
      (check (string= "firefox-linux" (getf snapshot :profile-id))
             "Profile provenance must retain stable profile identity.")
      (check (eq :browser (getf snapshot :backend))
             "Profile provenance must retain backend identity.")
      (check (eq :intercept (getf snapshot :capture-mode))
             "Profile provenance must retain actual capture mode.")
      (check (assoc "Sec-Fetch-Site" headers :test #'string=)
             "Safe static fetch metadata must remain in provenance.")
      (check (null (assoc "Authorization" headers :test #'string-equal))
             "Credential-bearing headers must not enter profile provenance."))
    t))