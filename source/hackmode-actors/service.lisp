;;;; Long-running Hackmode actor service entrypoint.
;;;
;;; Container and host entrypoint for the ontology actors: opens the
;;; operation database, spawns the actor topology, subscribes asset
;;; projection, and drains the durable StarIntel outbox on a fixed cadence
;;; until stopped. Health follows the fleet convention: when
;;; STARINTEL_SERVICE_HEALTH_FILE is set, its mtime advances every service
;;; loop iteration, so an idle-but-alive service stays healthy and a hung
;;; one goes stale.
(in-package :hackmode-actors)

(defvar *service-stop-requested* nil
  "Flag set by SIGTERM/SIGINT so the service loop exits cleanly.")

(defparameter +service-default-db-path+ "/var/lib/hackmode/operation"
  "Default operation database directory for the container service.")

(defparameter +service-default-drain-interval+ 30
  "Default seconds between outbox drains.")

(defun service-env (name &optional default)
  "Return environment variable NAME, or DEFAULT when unset or blank."
  (let ((value (uiop:getenv name)))
    (if (and (stringp value) (plusp (length value)))
        value
        default)))

(defun iso8601-now ()
  "Current UTC time as an ISO-8601 string for service log lines."
  (local-time:format-timestring
   nil (local-time:now)
   :format local-time:+iso-8601-format+))

(defun service-starintel-url ()
  "Resolve the ingest base URL; HACKMODE_STARINTEL_URL wins over the fleet's
STARINTEL_SERVER_URL."
  (service-env "HACKMODE_STARINTEL_URL" (service-env "STARINTEL_SERVER_URL")))

(defun service-starintel-api-key ()
  "Resolve the ingest credential; HACKMODE_STARINTEL_API_KEY wins over the
fleet's STARINTEL_API_KEY."
  (service-env "HACKMODE_STARINTEL_API_KEY" (service-env "STARINTEL_API_KEY")))

(defun service-starintel-config ()
  "Build the service STARINTEL-CONFIG from the environment.

Falls back to the core configuration defaults for anything unset, so the
same service image runs against any StarIntel Server without rebuilds."
  (hackmode:starintel-config-from-env
   :base-url (service-starintel-url)
   :api-key (service-starintel-api-key)
   :dataset (service-env "HACKMODE_STARINTEL_DATASET")))

(defun write-service-heartbeat (health-file)
  "Refresh HEALTH-FILE so an mtime-based probe sees the service alive."
  (when (and health-file (plusp (length health-file)))
    (with-open-file (stream health-file
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-line (iso8601-now) stream))))

(defun service-drain-once ()
  "Ask the ontology outbox actor to drain; returns its wire reply.

Drain failures are part of normal operation (server offline, credential
rotation): entries stay durable in the outbox and retry on the next cycle."
  (ask-hackmode-actor
   :outbox (make-ontology-wire-message "hackmode/drain-outbox@1" '())
   :timeout 60))

(defun install-service-signal-handlers ()
  "Request a clean stop on SIGTERM and SIGINT."
  (setf *service-stop-requested* nil)
  #+sbcl
  (progn
    (sb-sys:enable-interrupt sb-unix:sigterm
                             (lambda (&rest args)
                               (declare (ignore args))
                               (setf *service-stop-requested* t)))
    (sb-sys:enable-interrupt sb-unix:sigint
                             (lambda (&rest args)
                               (declare (ignore args))
                               (setf *service-stop-requested* t)))))

(defun seed-service-domains (&key (database hackmode:*db*))
  "Discover HACKMODE_SEED_DOMAINS assets once at service start.

Comma-separated domain names; each flows through the normal projection
loop into the durable outbox. This is the config-driven work source for
deployments before target dispatch lands."
  (let ((raw (service-env "HACKMODE_SEED_DOMAINS")))
    (when (and raw (plusp (length raw)))
      (dolist (name (remove "" (uiop:split-string raw :separator ",")
                            :test #'string=))
        (hackmode:discover-asset
         (make-instance 'hackmode:domain
                        :record (string-trim " " name)
                        :record-type "A"
                        :operation "hackmode-actor-service"
                        :date-added (hackmode:unix-now)
                        :date-updated (hackmode:unix-now))
         :database database)))))

(defun start-hackmode-actor-service (&key
                                       (db-path (service-env
                                                 "HACKMODE_DB_PATH"
                                                 +service-default-db-path+))
                                       (config (service-starintel-config)))
  "Open the operation database, spawn the ontology actors, and subscribe
asset projection. Returns the opened database."
  (setf hackmode:*starintel-config* config)
  ;; The projection layer keeps its own dataset default; the service is the
  ;; one place where the configured dataset must govern both transport and
  ;; projected documents.
  (setf *starintel-dataset* (hackmode:starintel-config-dataset config))
  ;; The ontology specs default to the source tree; a deployed image points
  ;; this at the baked-in copy instead.
  (let ((spec-directory (service-env "HACKMODE_ONTOLOGY_SPEC_DIR")))
    (when spec-directory
      (setf *ontology-spec-directory*
            (uiop:ensure-pathname spec-directory :ensure-directory t))))
  (ensure-directories-exist (uiop:ensure-pathname db-path
                                                  :defaults *default-pathname-defaults*
                                                  :ensure-directory t))
  (let ((database (tek9:new-database "operation" :path db-path)))
    (tek9:open-database database)
    (setf hackmode:*db* database)
    (ensure-hackmode-ontology-actors)
    (start-asset-projection-loop)
    (seed-service-domains :database database)
    database))

(defun stop-hackmode-actor-service (&optional (database hackmode:*db*))
  "Stop the actor topology and close the operation database."
  (stop-hackmode-ontology-actors)
  (hackmode:stop-hackmode-actor-system)
  (when (and database (tek9:db-is-open-p database))
    (tek9:close-database database))
  (when (eq database hackmode:*db*)
    (setf hackmode:*db* nil))
  t)

(defun run-hackmode-actor-service (&key
                                     (drain-interval
                                      (parse-integer
                                       (service-env "HACKMODE_DRAIN_INTERVAL_SECONDS"
                                                    (princ-to-string
                                                     +service-default-drain-interval+))))
                                     (health-file
                                      (service-env "STARINTEL_SERVICE_HEALTH_FILE"))
                                     (sleep-function #'sleep)
                                     (stream *standard-output*))
  "Run the actor service loop until a stop is requested.

Each iteration drains the outbox and refreshes the health heartbeat.
DRAIN-INTERVAL bounds the cadence; SLEEP-FUNCTION is injectable for tests."
  (install-service-signal-handlers)
  (loop until *service-stop-requested*
        do (progn
             (format stream "~&[hackmode-actors] ~a drain: ~s~%"
                     (iso8601-now)
                     (ignore-errors (service-drain-once)))
             (finish-output stream)
             (write-service-heartbeat health-file)
             (when *service-stop-requested*
               (return))
             (funcall sleep-function drain-interval)))
  (format stream "~&[hackmode-actors] ~a stop requested~%" (iso8601-now))
  (finish-output stream)
  t)

(defun hackmode-actor-service-main ()
  "Container entrypoint: start the service, run the loop, stop cleanly."
  (let ((database (start-hackmode-actor-service)))
    (unwind-protect
         (run-hackmode-actor-service)
      (stop-hackmode-actor-service database)))
  (uiop:quit 0))
