;;;; Operator surface for durable StarIntel delivery.
;;;
;;; STARINTEL-SYNC drains the persistent outbox through an authenticated
;;; transport built from the live configuration. Acknowledgement means the
;;; server accepted the document for ingest (:INGEST-ACCEPTED); it is never
;;; treated as proof of completed server-side storage.
(in-package :hackmode)

(defun starintel-sync-transport (config)
  "Return an HTTP ingest transport for CONFIG with send-time credentials."
  (make-starintel-http-transport
   :base-url (starintel-config-base-url config)
   :headers-function (lambda () (starintel-auth-headers config))
   :connect-timeout (starintel-config-connect-timeout config)
   :read-timeout (starintel-config-read-timeout config)))

(defun starintel-count-report (results)
  "Count processed outbox entries per resulting state."
  (let ((report (list :acked 0 :quarantined 0 :retried 0 :failed 0)))
    (dolist (entry results report)
      (case (outbox-entry-state entry)
        (:acknowledged (incf (getf report :acked)))
        (:quarantined (incf (getf report :quarantined)))
        (:retry (incf (getf report :retried)))
        (:failed (incf (getf report :failed)))))))

(defun starintel-remaining-count (database)
  "Count outbox entries still awaiting acknowledgement in DATABASE."
  (count-if (lambda (entry)
              (not (eq :acknowledged (outbox-entry-state entry))))
            (list-outbox-entries database)))

(defun starintel-sync (&key
                         (database *db*)
                         (config (current-starintel-config))
                         (limit 100)
                         (now (unix-now)))
  "Drain up to LIMIT due outbox entries to StarIntel Server and report.

Returns a plist with :ACKED :QUARANTINED :RETRIED :FAILED counts for entries
processed by this drain and :REMAINING entries still not acknowledged. A 2xx
server response is ingest acceptance, not a storage guarantee."
  (let* ((results (drain-outbox database (starintel-sync-transport config)
                                :now now :limit limit))
         (report (starintel-count-report results)))
    (nconc report (list :remaining (starintel-remaining-count database)))))

(defun print-starintel-sync-report (report &optional (stream *standard-output*))
  "Print a human summary of a STARINTEL-SYNC REPORT."
  (format stream
          "StarIntel sync: ~a acked (ingest-accepted, not proof of storage), ~
           ~a quarantined, ~a awaiting retry, ~a failed, ~a remaining.~%"
          (getf report :acked)
          (getf report :quarantined)
          (getf report :retried)
          (getf report :failed)
          (getf report :remaining))
  report)

(defun starintel-outbox-state-counts (database)
  "Return a plist of entry counts by outbox state in DATABASE."
  (let ((entries (list-outbox-entries database))
        (states '(:queued :sending :retry :quarantined :failed :acknowledged)))
    (nconc (list :total (length entries))
           (loop for state in states
                 append (list state
                              (count-if (lambda (entry)
                                          (eq state (outbox-entry-state entry)))
                                        entries))))))

(defun starintel-outbox-status (&key (database *db*) state)
  "Summarize durable outbox state in DATABASE, optionally filtered by STATE.

Returns the counts plist and, as a second value, the filtered entry list."
  (values (starintel-outbox-state-counts database)
          (list-outbox-entries database :state state)))
