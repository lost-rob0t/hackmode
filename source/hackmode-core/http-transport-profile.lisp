(in-package :hackmode)

(define-condition provider-transport-policy-error (error)
  ((reason :initarg :reason :reader provider-transport-policy-error-reason))
  (:report (lambda (condition stream)
             (format stream "Provider transport policy rejected execution: ~a"
                     (provider-transport-policy-error-reason condition)))))

(defstruct provider-transport-support
  (http-proxy-p nil :type boolean)
  (https-proxy-p nil :type boolean)
  (socks-p nil :type boolean)
  (browser-cdp-p nil :type boolean)
  (direct-only-p nil :type boolean)
  (capture-modes '(:unsupported) :type list))

(defstruct http-client-profile
  id
  version
  browser-family
  browser-version
  user-agent
  accept
  accept-language
  accept-encoding
  fetch-headers
  client-hints
  http-protocol
  backend
  capture-mode)

(defun normalize-capture-mode (mode)
  (unless (member mode '(:intercept :tunnel :direct :unsupported) :test #'eq)
    (error 'provider-transport-policy-error
           :reason (format nil "unknown capture mode ~s" mode)))
  mode)

(defun validate-provider-transport-support (support)
  (check-type support provider-transport-support)
  (let ((modes (provider-transport-support-capture-modes support)))
    (unless modes
      (error 'provider-transport-policy-error
             :reason "provider declares no capture modes"))
    (dolist (mode modes)
      (normalize-capture-mode mode))
    (when (and (provider-transport-support-direct-only-p support)
               (or (provider-transport-support-http-proxy-p support)
                   (provider-transport-support-https-proxy-p support)
                   (provider-transport-support-socks-p support)
                   (provider-transport-support-browser-cdp-p support)))
      (error 'provider-transport-policy-error
             :reason "direct-only provider also declares mediated transport"))
    support))

(defun http-client-profile-coherent-p (profile)
  "Return true when PROFILE is internally coherent enough for reproducible use.

This intentionally validates semantic consistency rather than pretending a
User-Agent string can model TLS/browser fingerprint behavior. Provider backends
remain responsible for implementing the declared backend/profile faithfully."
  (and (typep profile 'http-client-profile)
       (stringp (http-client-profile-id profile))
       (plusp (length (http-client-profile-id profile)))
       (stringp (http-client-profile-version profile))
       (plusp (length (http-client-profile-version profile)))
       (member (http-client-profile-http-protocol profile)
               '(:http1 :http2 :http3 :backend-default)
               :test #'eq)
       (member (http-client-profile-capture-mode profile)
               '(:intercept :tunnel :direct)
               :test #'eq)
       (or (not (eq :browser (http-client-profile-backend profile)))
           (and (http-client-profile-browser-family profile)
                (stringp (http-client-profile-browser-version profile))
                (stringp (http-client-profile-user-agent profile))))))

(defun validate-http-client-profile (profile)
  (unless (http-client-profile-coherent-p profile)
    (error 'provider-transport-policy-error
           :reason (format nil "incoherent HTTP client profile ~s"
                           (and (typep profile 'http-client-profile)
                                (http-client-profile-id profile)))))
  profile)

(defun select-http-client-profile (profiles &key profile-id)
  "Select one reproducible profile.

Explicit PROFILE-ID is authoritative. Without it, choose lexicographically by
stable profile ID so registry/hash ordering cannot alter replay behavior."
  (let ((validated (mapcar #'validate-http-client-profile profiles)))
    (or (when profile-id
          (find profile-id validated
                :key #'http-client-profile-id
                :test #'string=))
        (when (null profile-id)
          (first (sort (copy-list validated) #'string<
                       :key #'http-client-profile-id)))
        (error 'provider-transport-policy-error
               :reason (format nil "unknown HTTP client profile ~s" profile-id)))))

(defun resolve-provider-capture-mode (support requested-mode
                                      &key capture-required-p)
  "Resolve REQUESTED-MODE against typed SUPPORT without silent downgrade."
  (validate-provider-transport-support support)
  (let* ((requested (normalize-capture-mode requested-mode))
         (supported (provider-transport-support-capture-modes support)))
    (cond
      ((member requested supported :test #'eq)
       requested)
      (capture-required-p
       (error 'provider-transport-policy-error
              :reason (format nil "required capture mode ~s unsupported; provider supports ~s"
                              requested supported)))
      ((member :direct supported :test #'eq)
       :direct)
      ((member :unsupported supported :test #'eq)
       :unsupported)
      (t
       (error 'provider-transport-policy-error
              :reason (format nil "capture mode ~s unsupported; provider supports ~s"
                              requested supported))))))

(defun http-client-profile-provenance (profile)
  "Return the safe immutable profile snapshot suitable for execution evidence.

Only typed profile metadata is projected. Runtime headers carrying credentials,
cookies, authorization values, API keys, or other request secrets are never an
input to this function and therefore cannot leak into the snapshot."
  (validate-http-client-profile profile)
  (list :profile-id (http-client-profile-id profile)
        :profile-version (http-client-profile-version profile)
        :browser-family (http-client-profile-browser-family profile)
        :browser-version (http-client-profile-browser-version profile)
        :user-agent (http-client-profile-user-agent profile)
        :accept (http-client-profile-accept profile)
        :accept-language (http-client-profile-accept-language profile)
        :accept-encoding (http-client-profile-accept-encoding profile)
        :fetch-headers (copy-tree (http-client-profile-fetch-headers profile))
        :client-hints (copy-tree (http-client-profile-client-hints profile))
        :http-protocol (http-client-profile-http-protocol profile)
        :backend (http-client-profile-backend profile)
        :capture-mode (http-client-profile-capture-mode profile)))
