;;;; StarIntel integration configuration.
;;;
;;; Operator-facing configuration for every StarIntel client surface: ingest
;;; transport, read client, and sync commands. Values resolve from the
;;; environment first, with the existing StarIntel outbox defaults as
;;; fallbacks. The init file may override the cached configuration after
;;; loading via *STARINTEL-CONFIG-HOOK* or a direct SETF of *STARINTEL-CONFIG*.
(in-package :hackmode)

(defparameter +starintel-url-env-var+ "HACKMODE_STARINTEL_URL"
  "Environment variable overriding the StarIntel Server base URL.")

(defparameter +starintel-api-key-env-var+ "HACKMODE_STARINTEL_API_KEY"
  "Environment variable carrying the StarIntel API key.")

(defparameter +starintel-dataset-env-var+ "HACKMODE_STARINTEL_DATASET"
  "Environment variable overriding the default StarIntel dataset.")

(define-condition starintel-config-error (error)
  ((message :initarg :message :reader starintel-config-error-message))
  (:report (lambda (condition stream)
              (format stream "Invalid StarIntel configuration: ~a"
                      (starintel-config-error-message condition)))))

(defclass starintel-config ()
  ((base-url :initarg :base-url :reader starintel-config-base-url :type string)
   (api-key :initarg :api-key :reader starintel-config-api-key :type string)
   (dataset :initarg :dataset :reader starintel-config-dataset :type string)
   (connect-timeout :initarg :connect-timeout :reader starintel-config-connect-timeout
                    :initform 5 :type (integer 1))
   (read-timeout :initarg :read-timeout :reader starintel-config-read-timeout
                 :initform 10 :type (integer 1)))
  (:documentation "Connection settings for one StarIntel Server endpoint."))

(defmethod print-object ((config starintel-config) stream)
  ;; Credential masking applies to configuration objects only; captured
  ;; operation evidence keeps its exact observed values elsewhere.
  (print-unreadable-object (config stream :type t :identity t)
    (format stream "base-url ~s dataset ~s api-key ~:[absent~;masked~]"
            (starintel-config-base-url config)
            (starintel-config-dataset config)
            (plusp (length (starintel-config-api-key config))))))

(defun starintel-trailing-slash-trimmed (url)
  (string-right-trim "/" url))

(defun valid-starintel-base-url-p (url)
  "Return true when URL is an absolute HTTP or HTTPS URL with a host."
  (and (stringp url)
       (plusp (length url))
       (handler-case
           (let ((parsed (quri:uri url)))
             (and (member (quri:uri-scheme parsed) '("http" "https") :test #'string=)
                  (quri:uri-host parsed)
                  (plusp (length (quri:uri-host parsed)))))
         (error () nil))))

(defun starintel-env-value (raw default)
  "Resolve environment value RAW, treating NIL or an empty string as absent."
  (if (and (stringp raw) (plusp (length raw)))
      raw
      default))

(defun starintel-config-from-env (&key
                                    (base-url (uiop:getenv +starintel-url-env-var+))
                                    (api-key (uiop:getenv +starintel-api-key-env-var+))
                                    (dataset (uiop:getenv +starintel-dataset-env-var+))
                                    (connect-timeout 5)
                                    (read-timeout 10))
  "Build a STARINTEL-CONFIG from environment overrides and built-in defaults.

  HACKMODE_STARINTEL_URL        StarIntel Server base URL
                                (default *STARINTEL-INGEST-BASE-URL*)
  HACKMODE_STARINTEL_API_KEY    Bearer key; empty means anonymous
  HACKMODE_STARINTEL_DATASET    dataset name (default *STARINTEL-DATASET*)

Signals STARINTEL-CONFIG-ERROR when the base URL is not an HTTP(S) URL or the
dataset name is blank."
  (let ((resolved-url (starintel-env-value base-url *starintel-ingest-base-url*))
        (resolved-key (starintel-env-value api-key ""))
        (resolved-dataset (starintel-env-value dataset *starintel-dataset*)))
    (unless (valid-starintel-base-url-p resolved-url)
      (error 'starintel-config-error
             :message (format nil "base URL ~s is not an absolute http(s) URL"
                              resolved-url)))
    (unless (and (stringp resolved-dataset) (plusp (length resolved-dataset)))
      (error 'starintel-config-error
             :message "dataset name must be a non-empty string"))
    (make-instance 'starintel-config
                   :base-url (starintel-trailing-slash-trimmed resolved-url)
                   :api-key resolved-key
                   :dataset resolved-dataset
                   :connect-timeout connect-timeout
                   :read-timeout read-timeout)))

(defvar *starintel-config* nil
  "Cached active STARINTEL-CONFIG. Reload with RELOAD-STARINTEL-CONFIG.")

(defvar *starintel-config-hook*
  (make-instance 'nhooks:hook-void :handlers nil)
  "Hook run after RELOAD-STARINTEL-CONFIG refreshes *STARINTEL-CONFIG*.

Handlers take no arguments. An init.lisp can install a handler that replaces
the environment-derived configuration, e.g.

  (nhooks:add-hook hackmode:*starintel-config-hook*
                   (lambda ()
                     (setf hackmode:*starintel-config*
                             (make-instance 'hackmode:starintel-config
                                            :base-url \"https://star.example\"
                                            :api-key \"star_sk_v1_...\"
                                            :dataset \"star-intel\"))))

or simply SETF *STARINTEL-CONFIG* directly from init.lisp after calling
RELOAD-STARINTEL-CONFIG.")

(defun reload-starintel-config ()
  "Rebuild *STARINTEL-CONFIG* from the environment and return it.

Handlers on *STARINTEL-CONFIG-HOOK* run after the environment value is cached
so init-file customization layers on top of the environment rather than
silently discarding it."
  (setf *starintel-config* (starintel-config-from-env))
  (nhooks:run-hook *starintel-config-hook*)
  *starintel-config*)

(defun current-starintel-config ()
  "Return the cached STARINTEL-CONFIG, loading it from env on first use."
  (or *starintel-config* (reload-starintel-config)))

(defun starintel-auth-headers (config)
  "Return request headers authenticating CONFIG against StarIntel Server.

The key value stays out of outbox records; transports build headers at send
time from the live configuration."
  (let ((key (starintel-config-api-key config)))
    (if (and (stringp key) (plusp (length key)))
        `(("Authorization" . ,(format nil "Bearer ~a" key)))
        '())))
