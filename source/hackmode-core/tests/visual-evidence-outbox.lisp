(defpackage :hackmode-visual-evidence-outbox-tests
  (:use :cl))

(in-package :hackmode-visual-evidence-outbox-tests)

(defun fresh-test-path ()
  (merge-pathnames
   (format nil "hackmode-visual-outbox-~a/" (tek9:make-key-id))
   (uiop:temporary-directory)))

(defun remove-test-path (path)
  (ignore-errors
    (uiop:delete-directory-tree path :validate t :if-does-not-exist :ignore)))

(defun fixture-record ()
  (hackmode-database:make-visual-evidence-record
   :operation-id "op-visual"
   :run-id "run-1"
   :job-id "shot-1"
   :asset-id "asset-url-1"
   :requested-url "https://example.test/start"
   :final-url "https://example.test/final"
   :screenshot-evidence-ref "evidence://screens/shot-1.png"
   :screenshot-digest "sha256:abc123"
   :captured-at "2026-08-31T23:30:00Z"
   :title "Example"
   :http-status 200
   :viewport '(:width 1440 :height 900)
   :client-profile-id "chrome-140-linux"
   :browser-id "chromium"
   :browser-version "140.0"
   :duration-ms 125
   :body-digest "sha256:def456"
   :technology-hints '("nginx" "h2")
   :capture-session-id "capture-1"
   :exchange-id "exchange-9"
   :provenance '(:producer "browser-worker"
                 :authorization "Bearer secret-must-not-project"
                 :cookie "sid=secret-must-not-project")))

(defun run-visual-evidence-outbox-tests ()
  (let* ((root (fresh-test-path))
         (db (tek9:new-database "operation" :path root))
         (record (fixture-record)))
    (unwind-protect
         (progn
           (tek9:open-database db)
           ;; Local canonical evidence is persisted before remote projection.
           (hackmode-database:persist-visual-evidence-record db record)
           (assert
            (hackmode-database:fetch-visual-evidence-record
             db "op-visual"
             (hackmode-database:visual-evidence-record-record-id record)))

           ;; Projection is deterministic, bounded, and excludes raw secret-bearing provenance.
           (let* ((json (hackmode:visual-evidence->starintel-json record))
                  (json-again (hackmode:visual-evidence->starintel-json record))
                  (wire (jsown:to-json json)))
             (assert (string= (jsown:to-json json) (jsown:to-json json-again)))
             (assert (string= "document" (jsown:val json "dtype")))
             (assert (search "sha256:abc123" wire))
             (assert (search "evidence://screens/shot-1.png" wire))
             (assert (search "exchange-9" wire))
             (assert (not (search "Bearer secret-must-not-project" wire)))
             (assert (not (search "sid=secret-must-not-project" wire))))

           ;; Repeated enqueue collapses onto one durable logical outbox record.
           (multiple-value-bind (entry created-p)
               (hackmode:enqueue-visual-evidence-for-starintel record :database db :now 1000)
             (assert created-p)
             (multiple-value-bind (same duplicate-created-p)
                 (hackmode:enqueue-visual-evidence-for-starintel record :database db :now 1001)
               (assert (not duplicate-created-p))
               (assert (string= (hackmode:outbox-entry-id entry)
                                (hackmode:outbox-entry-id same))))

             ;; Publish/transport failure leaves local evidence intact and the projection retryable.
             (hackmode:process-outbox-entry
              db entry
              (lambda (ignored)
                (declare (ignore ignored))
                (error 'hackmode:outbox-transport-error :message "offline"))
              :now 1002)
             (assert (eq :retry (hackmode:outbox-entry-state entry)))
             (assert
              (hackmode-database:fetch-visual-evidence-record
               db "op-visual"
               (hackmode-database:visual-evidence-record-record-id record)))

             ;; Only an accepted response acknowledges delivery.
             (hackmode:process-outbox-entry
              db entry
              (lambda (ignored)
                (declare (ignore ignored))
                (values 202 "accepted"))
              :now (hackmode:outbox-entry-next-attempt-at entry))
             (assert (eq :acknowledged (hackmode:outbox-entry-state entry)))
             (assert (eq :ingest-accepted (hackmode:outbox-entry-ack-kind entry)))
             (assert (= 1 (length (hackmode:list-outbox-entries db))))))
      (when (tek9:db-is-open-p db)
        (tek9:close-database db))
      (remove-test-path root)))
  t)
