(in-package :hackmode)

(defstruct capture-process-spec
  operation-id
  capture-session-id
  endpoint
  spool-id
  spool-path
  (addon-path "tools/ipx/mitmproxy-addon.py" :type string)
  (format-version 1 :type integer)
  (program "mitmdump" :type string)
  arguments)

(defstruct (capture-service (:constructor %make-capture-service))
  operation-id
  capture-session-id
  endpoint
  spool-id
  (version 1 :type integer)
  (state :stopped)
  process-id
  (restart-count 0 :type integer)
  (max-restarts 2 :type integer)
  failure-class
  last-error
  runner
  stopper
  process-spec)

(defun capture-non-empty-string (value label)
  (unless (and (stringp value) (plusp (length value)))
    (error "~a must be a non-empty string." label))
  (copy-seq value))

(defun capture-session-identity (operation-id endpoint spool-id)
  (starintel:digest-id "hackmode-capture-session-v1"
                       operation-id
                       endpoint
                       spool-id))

(defun capture-endpoint-host-port (endpoint)
  (multiple-value-bind (match groups)
      (cl-ppcre:scan-to-strings "^http://([^:/]+):([0-9]+)$" endpoint)
    (declare (ignore match))
    (unless groups
      (error "Capture endpoint must use http://HOST:PORT, got ~s." endpoint))
    (values (aref groups 0)
            (parse-integer (aref groups 1)))))

(defun capture-addon-setting (name value)
  (format nil "~a=~a" name value))

(defun make-capture-process-specification (operation-id capture-session-id
                                           endpoint spool-id spool-path
                                           addon-path format-version program)
  (multiple-value-bind (host port)
      (capture-endpoint-host-port endpoint)
    (make-capture-process-spec
     :operation-id (copy-seq operation-id)
     :capture-session-id (copy-seq capture-session-id)
     :endpoint (copy-seq endpoint)
     :spool-id (copy-seq spool-id)
     :spool-path (copy-seq spool-path)
     :addon-path (copy-seq addon-path)
     :format-version format-version
     :program (copy-seq program)
     :arguments (list "--listen-host" host
                      "--listen-port" (write-to-string port)
                      "-s" (copy-seq addon-path)
                      "--set" (capture-addon-setting
                               "hackmode_operation_id" operation-id)
                      "--set" (capture-addon-setting
                               "hackmode_capture_session_id" capture-session-id)
                      "--set" (capture-addon-setting
                               "hackmode_spool_id" spool-id)
                      "--set" (capture-addon-setting
                               "hackmode_spool_path" spool-path)
                      "--set" (capture-addon-setting
                               "hackmode_ipx_version" format-version)))))

(defun default-capture-process-runner (spec)
  "Spawn mitmdump for SPEC without granting the subprocess persistence authority."
  (uiop:launch-program
   (cons (capture-process-spec-program spec)
         (capture-process-spec-arguments spec))
   :input :null
   :output :interactive
   :error-output :interactive
   :wait nil))

(defun default-capture-process-stopper (process-id)
  "Terminate a live capture process returned by UIOP:LAUNCH-PROGRAM."
  (uiop:terminate-process process-id)
  t)

(defun launch-capture-process (service)
  (setf (capture-service-state service) :starting
        (capture-service-failure-class service) nil
        (capture-service-last-error service) nil)
  (handler-case
      (let ((process-id
              (funcall (capture-service-runner service)
                       (capture-service-process-spec service))))
        (unless process-id
          (error "Capture process runner returned no process identity."))
        (setf (capture-service-process-id service) process-id
              (capture-service-state service) :running)
        service)
    (error (condition)
      (setf (capture-service-process-id service) nil
            (capture-service-state service) :failed
            (capture-service-failure-class service) :spawn-failed
            (capture-service-last-error service) (format nil "~a" condition))
      service)))

(defun start-capture-service (operation-id
                              &key capture-session-id endpoint spool-id spool-path
                                (addon-path "tools/ipx/mitmproxy-addon.py")
                                (format-version 1)
                                (program "mitmdump")
                                (max-restarts 2)
                                (runner #'default-capture-process-runner)
                                (stopper #'default-capture-process-stopper))
  "Start one operation-scoped mitmdump capture service and return typed state.

RUNNER and STOPPER are injected process boundaries so lifecycle behavior can be
tested without subprocesses. The mitmdump addon writes append-only source
evidence to SPOOL-PATH; it has no Tek9, KB, or StarIntel mutation path."
  (let* ((operation (capture-non-empty-string operation-id "operation-id"))
         (proxy-endpoint (capture-non-empty-string endpoint "endpoint"))
         (spool (capture-non-empty-string spool-id "spool-id"))
         (spool-file (capture-non-empty-string (or spool-path spool-id)
                                               "spool-path"))
         (addon (capture-non-empty-string addon-path "addon-path"))
         (session (capture-non-empty-string
                   (or capture-session-id
                       (capture-session-identity operation proxy-endpoint spool))
                   "capture-session-id"))
         (program-name (capture-non-empty-string program "program")))
    (unless (and (integerp format-version) (plusp format-version))
      (error "format-version must be a positive integer."))
    (unless (and (integerp max-restarts) (not (minusp max-restarts)))
      (error "max-restarts must be a non-negative integer."))
    (check-type runner function)
    (check-type stopper function)
    (let ((service
            (%make-capture-service
             :operation-id operation
             :capture-session-id session
             :endpoint proxy-endpoint
             :spool-id spool
             :version format-version
             :state :stopped
             :max-restarts max-restarts
             :runner runner
             :stopper stopper
             :process-spec
             (make-capture-process-specification
              operation session proxy-endpoint spool spool-file addon
              format-version program-name))))
      (launch-capture-process service))))

(defun note-capture-process-exit (service &key exit-code)
  "Record unexpected process exit and restart SERVICE within its fixed budget."
  (check-type service capture-service)
  (when (member (capture-service-state service) '(:stopping :stopped))
    (return-from note-capture-process-exit service))
  (setf (capture-service-process-id service) nil
        (capture-service-state service) :degraded
        (capture-service-last-error service)
        (format nil "Capture process exited~@[ with status ~a~]." exit-code))
  (if (< (capture-service-restart-count service)
         (capture-service-max-restarts service))
      (progn
        (incf (capture-service-restart-count service))
        (launch-capture-process service))
      (progn
        (setf (capture-service-state service) :failed
              (capture-service-failure-class service) :restart-exhausted)
        service)))

(defun stop-capture-service (service)
  "Stop SERVICE explicitly without triggering restart behavior."
  (check-type service capture-service)
  (when (eq :stopped (capture-service-state service))
    (return-from stop-capture-service service))
  (let ((process-id (capture-service-process-id service)))
    (setf (capture-service-state service) :stopping)
    (when process-id
      (handler-case
          (funcall (capture-service-stopper service) process-id)
        (error (condition)
          (setf (capture-service-last-error service) (format nil "~a" condition)))))
    (setf (capture-service-process-id service) nil
          (capture-service-state service) :stopped)
    service))
