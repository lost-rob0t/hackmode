(in-package :hackmode)

(defparameter +visual-evidence-starintel-id-version+
  "hackmode-visual-evidence-starintel-v1")

(defun %visual-evidence-starintel-id (record)
  (starintel:digest-id
   +visual-evidence-starintel-id-version+
   (hackmode-database:visual-evidence-record-operation-id record)
   (hackmode-database:visual-evidence-record-record-id record)))

(defun %set-json-field (object key value)
  (when value
    (setf (jsown:val object key) value))
  object)

(defun visual-evidence->starintel-json (record &key (dataset *starintel-dataset*))
  "Project accepted local visual evidence into a deterministic StarIntel document.

Only typed visual-recon fields are projected. RECORD's free-form provenance is
intentionally excluded so secret-bearing provider metadata remains local."
  (let ((data (jsown:empty-object))
        (provenance (jsown:empty-object)))
    (%set-json-field data "asset_id"
                     (hackmode-database:visual-evidence-record-asset-id record))
    (%set-json-field data "requested_url"
                     (hackmode-database:visual-evidence-record-requested-url record))
    (%set-json-field data "final_url"
                     (hackmode-database:visual-evidence-record-final-url record))
    (%set-json-field data "screenshot_evidence_ref"
                     (hackmode-database:visual-evidence-record-screenshot-evidence-ref record))
    (%set-json-field data "screenshot_digest"
                     (hackmode-database:visual-evidence-record-screenshot-digest record))
    (%set-json-field data "captured_at"
                     (hackmode-database:visual-evidence-record-captured-at record))
    (%set-json-field data "title"
                     (hackmode-database:visual-evidence-record-title record))
    (%set-json-field data "http_status"
                     (hackmode-database:visual-evidence-record-http-status record))
    (%set-json-field data "viewport"
                     (hackmode-database:visual-evidence-record-viewport record))
    (%set-json-field data "client_profile_id"
                     (hackmode-database:visual-evidence-record-client-profile-id record))
    (%set-json-field data "browser_id"
                     (hackmode-database:visual-evidence-record-browser-id record))
    (%set-json-field data "browser_version"
                     (hackmode-database:visual-evidence-record-browser-version record))
    (%set-json-field data "duration_ms"
                     (hackmode-database:visual-evidence-record-duration-ms record))
    (%set-json-field data "body_digest"
                     (hackmode-database:visual-evidence-record-body-digest record))
    (%set-json-field data "technology_hints"
                     (copy-list
                      (hackmode-database:visual-evidence-record-technology-hints record)))
    (%set-json-field data "capture_session_id"
                     (hackmode-database:visual-evidence-record-capture-session-id record))
    (%set-json-field data "exchange_id"
                     (hackmode-database:visual-evidence-record-exchange-id record))
    (%set-json-field data "failure_classification"
                     (hackmode-database:visual-evidence-record-failure-classification record))

    (%set-json-field provenance "operation"
                     (hackmode-database:visual-evidence-record-operation-id record))
    (%set-json-field provenance "run_id"
                     (hackmode-database:visual-evidence-record-run-id record))
    (%set-json-field provenance "job_id"
                     (hackmode-database:visual-evidence-record-job-id record))
    (%set-json-field provenance "local_record_id"
                     (hackmode-database:visual-evidence-record-record-id record))
    (%set-json-field provenance "producer" "hackmode-visual-recon")

    (starintel:encode
     (make-instance
      'starintel:document
      :id (%visual-evidence-starintel-id record)
      :dataset dataset
      :date-added (hackmode-database:visual-evidence-record-captured-at record)
      :date-updated (hackmode-database:visual-evidence-record-captured-at record)
      :title (or (hackmode-database:visual-evidence-record-title record) "")
      :tags '("visual-recon" "cyber-evidence")
      :related-ids
      (remove nil
              (list
               (hackmode-database:visual-evidence-record-asset-id record)
               (hackmode-database:visual-evidence-record-exchange-id record)
               (hackmode-database:visual-evidence-record-capture-session-id record)))
      :provenance provenance
      :data data))))

(defun enqueue-visual-evidence-for-starintel
    (record &key (database *db*) (now (unix-now)))
  "Durably queue RECORD for StarIntel ingest through the canonical outbox.

This function does not transmit directly. Repeated projection of the same typed
record collapses to the existing deterministic outbox entry."
  (enqueue-starintel-json
   database
   (visual-evidence->starintel-json record)
   :operation (hackmode-database:visual-evidence-record-operation-id record)
   :now now))
