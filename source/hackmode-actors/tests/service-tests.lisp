(in-package :hackmode-actors-tests)

;;; Long-running service entrypoint: environment resolution, heartbeat, and
;;; the full start -> drain -> stop lifecycle against a dead endpoint (the
;;; durable outbox keeps entries and reports state; nothing raises).

(defun run-service-env-tests ()
  ;; Blank and unset variables fall back to the provided default.
  (setf (uiop:getenv "HACKMODE_SERVICE_TEST_UNSET") "")
  (setf (uiop:getenv "HACKMODE_SERVICE_TEST_BLANK") "")
  (assert (string= "fallback"
                   (hackmode-actors:service-env
                    "HACKMODE_SERVICE_TEST_UNSET" "fallback")))
  (assert (string= "fallback"
                   (hackmode-actors:service-env
                    "HACKMODE_SERVICE_TEST_BLANK" "fallback")))
  ;; Set values are used verbatim.
  (setf (uiop:getenv "HACKMODE_SERVICE_TEST_SET") "value")
  (assert (string= "value"
                   (hackmode-actors:service-env
                    "HACKMODE_SERVICE_TEST_SET" "fallback")))
  (setf (uiop:getenv "HACKMODE_SERVICE_TEST_SET") "")
  ;; The service configuration prefers HACKMODE_* names and falls back to
  ;; the fleet's STARINTEL_* names.
  (setf (uiop:getenv "STARINTEL_SERVER_URL") "http://fleet.example")
  (setf (uiop:getenv "STARINTEL_API_KEY") "fleet-key")
  (setf (uiop:getenv "HACKMODE_STARINTEL_URL") "")
  (setf (uiop:getenv "HACKMODE_STARINTEL_API_KEY") "")
  (setf (uiop:getenv "HACKMODE_STARINTEL_DATASET") "fleet-dataset")
  (let ((config (hackmode-actors:service-starintel-config)))
    (assert (string= "http://fleet.example"
                     (hackmode:starintel-config-base-url config)))
    (assert (string= "fleet-key"
                     (hackmode:starintel-config-api-key config)))
    (assert (string= "fleet-dataset"
                     (hackmode:starintel-config-dataset config))))
  ;; The Hackmode-specific names win over the fleet names.
  (setf (uiop:getenv "HACKMODE_STARINTEL_URL") "http://hackmode.example/")
  (setf (uiop:getenv "HACKMODE_STARINTEL_API_KEY") "hackmode-key")
  (let ((config (hackmode-actors:service-starintel-config)))
    (assert (string= "http://hackmode.example"
                     (hackmode:starintel-config-base-url config)))
    (assert (string= "hackmode-key"
                     (hackmode:starintel-config-api-key config))))
  ;; Heartbeat file is created and refreshed.
  (let ((health (merge-pathnames
                 (format nil "hm-service-health-~a" (tek9:make-key-id))
                 (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (hackmode-actors:write-service-heartbeat (namestring health))
           (assert (uiop:file-exists-p health))
           (sleep 0.01)
           (hackmode-actors:write-service-heartbeat (namestring health))
           (assert (uiop:file-exists-p health)))
      (uiop:delete-file-if-exists health)))
  ;; A nil or blank heartbeat path is a no-op.
  (assert (null (hackmode-actors:write-service-heartbeat nil)))
  (assert (null (hackmode-actors:write-service-heartbeat "")))
  ;; Reset the environment the tests touched.
  (setf (uiop:getenv "STARINTEL_SERVER_URL") "")
  (setf (uiop:getenv "STARINTEL_API_KEY") "")
  (setf (uiop:getenv "HACKMODE_STARINTEL_URL") "")
  (setf (uiop:getenv "HACKMODE_STARINTEL_API_KEY") "")
  (setf (uiop:getenv "HACKMODE_STARINTEL_DATASET") "")
  t)

(defun run-service-lifecycle-test ()
  (hackmode-actors:stop-hackmode-ontology-actors)
  (let* ((root (fresh-test-path "hm-service-db"))
         (previous-config hackmode:*starintel-config*)
         (previous-db hackmode:*db*)
         (health (merge-pathnames
                  (format nil "hm-service-health-~a" (tek9:make-key-id))
                  (uiop:temporary-directory))))
    (unwind-protect
         (progn
           ;; The service starts against an unreachable endpoint: the drain
           ;; cannot succeed, but must stay durable and non-fatal.
           (setf (uiop:getenv "HACKMODE_STARINTEL_URL")
                 "http://127.0.0.1:9")
           (setf (uiop:getenv "HACKMODE_STARINTEL_API_KEY") "test-key")
           (let ((database
                   (hackmode-actors:start-hackmode-actor-service
                    :db-path (namestring (uiop:ensure-pathname root :ensure-directory nil)))))
             (assert (tek9:db-is-open-p database))
             (assert (eq database hackmode:*db*))
             (assert (= 6 (length hackmode-actors:*ontology-actors*)))
             ;; Discovering an asset flows through the projection loop into
             ;; the durable outbox.
             (hackmode:discover-asset
              (make-instance 'hackmode:domain
                             :record "service-lifecycle.example"
                             :record-type "A"
                             :operation "hm-service-test"
                             :date-added 1000
                             :date-updated 1000)
              :database database)
             ;; One service iteration: drain against the dead endpoint and
             ;; refresh the heartbeat, then stop.
             (let ((hackmode-actors:*service-stop-requested* nil))
               (flet ((stop-immediately (seconds)
                        (declare (ignore seconds))
                        (setf hackmode-actors:*service-stop-requested* t)))
                 (hackmode-actors:run-hackmode-actor-service
                  :drain-interval 1
                  :health-file (namestring health)
                  :sleep-function #'stop-immediately
                  :stream (make-broadcast-stream)))
               (assert (uiop:file-exists-p health))
               (assert hackmode-actors:*service-stop-requested*))
             ;; The entry stayed durable (retry, not acknowledged) because
             ;; the endpoint is unreachable.
             (let ((counts (hackmode:starintel-outbox-state-counts database)))
               (assert (plusp (getf counts :total)) ()
                       "expected a durable outbox entry after discovery")
               (assert (zerop (getf counts :acknowledged)) ()
                       "unreachable endpoint must not acknowledge"))
             ;; Stopping closes the database and clears the global.
             (hackmode-actors:stop-hackmode-actor-service database)
             (assert (not (tek9:db-is-open-p database)))
             (assert (null hackmode:*db*))
             (assert (null hackmode-actors:*ontology-actors*))))
      ;; Restore what the test replaced.
      (setf (uiop:getenv "HACKMODE_STARINTEL_URL") "")
      (setf (uiop:getenv "HACKMODE_STARINTEL_API_KEY") "")
      (setf hackmode:*starintel-config* previous-config)
      (setf hackmode:*db* previous-db)
      (hackmode-actors:stop-hackmode-ontology-actors)
      (uiop:delete-file-if-exists health)
      (remove-test-path root)))
  t)
