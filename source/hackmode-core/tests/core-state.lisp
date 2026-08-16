(defpackage :hackmode-tests
  (:use :cl))

(in-package :hackmode-tests)

(defun assert-equal (expected actual &optional (label "values"))
  (assert (equal expected actual) ()
          "Expected ~a to be ~s, got ~s" label expected actual))

(defun fresh-test-path (prefix)
  (merge-pathnames
   (format nil "~a-~a/" prefix (tek9:make-key-id))
   (uiop:temporary-directory)))

(defun remove-test-path (path)
  (ignore-errors
    (uiop:delete-directory-tree path :validate t :if-does-not-exist :ignore)))

(defun wait-until (predicate &key (attempts 200) (delay 0.01))
  (loop repeat attempts
        when (funcall predicate) return t
        do (sleep delay)
        finally (return nil)))

(defun run-instance-state-test ()
  (let ((left (make-instance 'hackmode:domain
                             :record "left.example"
                             :tags '("left")))
        (right (make-instance 'hackmode:domain
                              :record "right.example"
                              :tags '("right")))
        (op-a (make-instance 'hackmode:operation :name "a" :dir "/tmp/a/"))
        (op-b (make-instance 'hackmode:operation :name "b" :dir "/tmp/b/")))
    (assert (not (string= (hackmode:doc-id left) (hackmode:doc-id right))))
    (setf (hackmode:doc-tags left) '("changed"))
    (assert-equal '("right") (hackmode:doc-tags right) "instance-local tags")
    (assert-equal "a" (hackmode:operation-name op-a) "operation A")
    (assert-equal "b" (hackmode:operation-name op-b) "operation B")))

(defun run-operation-registry-test ()
  (let* ((root (fresh-test-path "hackmode-operations"))
         (workspace (fresh-test-path "hackmode-workspace"))
         (hackmode:*operations-database*
           (tek9:new-database "operations" :path root)))
    (unwind-protect
         (progn
           (hackmode:new-operation "alpha" workspace "test operation")
           (assert-equal "alpha"
                         (hackmode:operation-name
                          (hackmode:select-operation "alpha"))
                         "selected operation")
           (tek9:close-database hackmode:*operations-database*)
           (hackmode:ensure-operations-database-open)
           (assert-equal '("alpha")
                         (mapcar #'hackmode:operation-name
                                 (hackmode:list-operations))
                         "reopened operation registry"))
      (when (tek9:db-is-open-p hackmode:*operations-database*)
        (tek9:close-database hackmode:*operations-database*))
      (remove-test-path root)
      (remove-test-path workspace))))

(defun run-starintel-projection-test ()
  (let* ((asset (make-instance 'hackmode:domain
                               :record "Example.COM."
                               :record-type "a"
                               :operation "op-alpha"
                               :tool "crt.sh"
                               :date-added 100
                               :date-updated 200
                               :tags '("dns" "ct")))
         (_normalized (hackmode:normalize-asset asset))
         (document (hackmode:asset->starintel-document asset))
         (json (hackmode:asset->starintel-json asset))
         (json-again (hackmode:asset->starintel-json asset)))
    (declare (ignore _normalized))
    (assert (typep document 'starintel:domain))
    (assert-equal "example.com" (starintel:domain-record document)
                  "StarIntel domain record")
    (assert-equal "A" (starintel:domain-record-type document)
                  "StarIntel record type")
    (assert-equal (starintel:doc-id document)
                  (hackmode:asset-deterministic-id asset)
                  "shared canonical domain id")
    (assert-equal (jsown:to-json json)
                  (jsown:to-json json-again)
                  "stable repeated StarIntel projection")
    (assert-equal "domain" (jsown:val json "dtype") "wire dtype")
    (assert-equal "example.com"
                  (jsown:val (jsown:val json "data") "record")
                  "wire domain record")
    (assert-equal "op-alpha"
                  (jsown:val (jsown:val json "provenance") "operation")
                  "wire operation provenance"))
  (let ((unresolved (make-instance 'hackmode:host
                                   :hostname "Pending.Example"
                                   :ip "")))
    (hackmode:normalize-asset unresolved)
    (assert (null (hackmode:asset->starintel-document unresolved)) ()
            "Unresolved host must not collapse onto StarIntel empty-IP identity.")))

(defun run-asset-lifecycle-test ()
  (let* ((root (fresh-test-path "hackmode-assets"))
         (db (tek9:new-database "assets" :path root))
         (events 0)
         (legacy-domain-events 0)
         (hackmode:*asset-event-hook*
           (make-instance 'nhooks:hook-any :handlers nil))
         (hackmode:*domain-hook*
           (make-instance 'nhooks:hook-any :handlers nil)))
    (unwind-protect
         (progn
           (tek9:open-database db)
           (hackmode:subscribe-asset-events
            (lambda (event)
              (assert (eq :discovered
                          (hackmode:asset-event-event-type event)))
              (let* ((asset (hackmode:asset-event-asset event))
                     (persisted (tek9:fetch* db (hackmode:doc-id asset))))
                (assert persisted ()
                        "Asset event fired before local persistence."))
              (incf events)))
           (nhooks:add-hook hackmode:*domain-hook*
                            (lambda (domain)
                              (declare (ignore domain))
                              (incf legacy-domain-events)))
           (let ((first (make-instance 'hackmode:domain
                                       :record "Example.COM."
                                       :record-type "a"))
                 (second (make-instance 'hackmode:domain
                                        :record "example.com"
                                        :record-type "A")))
             (multiple-value-bind (stored created-p persisted-p)
                 (hackmode:record-recon-asset first :database db)
               (assert created-p)
               (assert persisted-p)
               (assert-equal "example.com" (hackmode:domain-name stored)
                             "normalized domain")
               (assert-equal (starintel:doc-id
                              (hackmode:asset->starintel-document stored))
                             (hackmode:doc-id stored)
                             "persisted canonical StarIntel id"))
             (multiple-value-bind (stored created-p persisted-p)
                 (hackmode:record-recon-asset second :database db)
               (declare (ignore stored))
               (assert persisted-p)
               (assert (not created-p)))
             (assert (= events 1))
             (assert (= legacy-domain-events 1))
             (assert (= 1 (length (hackmode:query-assets
                                   :database db
                                   :type :domain))))))
      (when (tek9:db-is-open-p db)
        (tek9:close-database db))
      (remove-test-path root))))

(defun run-outbox-lifecycle-test ()
  (let* ((root (fresh-test-path "hackmode-outbox"))
         (db (tek9:new-database "operation" :path root))
         (asset (make-instance 'hackmode:domain
                               :record "offline.example"
                               :record-type "A"
                               :operation "offline-op"
                               :date-added 1000
                               :date-updated 1000))
         (calls 0)
         (transport
           (lambda (entry)
             (declare (ignore entry))
             (incf calls)
             (if (= calls 1)
                 (error 'hackmode:outbox-transport-error
                        :message "server offline")
                 (values 202 "accepted"))))
         (hackmode:*outbox-max-attempts* 3))
    (unwind-protect
         (progn
           (tek9:open-database db)
           ;; Enqueue is durable and byte-identical repeated projection dedupes.
           (multiple-value-bind (entry created-p)
               (hackmode:enqueue-asset-for-starintel asset :database db :now 1000)
             (assert created-p)
             (multiple-value-bind (same duplicate-created-p)
                 (hackmode:enqueue-asset-for-starintel asset :database db :now 1001)
               (assert (not duplicate-created-p))
               (assert-equal (hackmode:outbox-entry-id entry)
                             (hackmode:outbox-entry-id same)
                             "duplicate enqueue id"))
             (tek9:close-database db)
             (tek9:open-database db)
             (let ((reloaded (hackmode:fetch-outbox-entry
                              db (hackmode:outbox-entry-id entry))))
               (assert reloaded () "Queued outbox entry did not survive reopen.")
               (assert (eq :queued (hackmode:outbox-entry-state reloaded)))
               ;; Offline transport moves to retry without affecting operation data.
               (hackmode:process-outbox-entry db reloaded transport :now 1010)
               (assert (eq :retry (hackmode:outbox-entry-state reloaded)))
               (assert (= 1 (hackmode:outbox-entry-attempts reloaded)))
               (assert (= 1012 (hackmode:outbox-entry-next-attempt-at reloaded)))
               (hackmode:discover-asset
                (make-instance 'hackmode:domain
                               :record "still-working.example"
                               :record-type "A")
                :database db)
               (assert (= 1 (length (hackmode:query-assets
                                     :database db :type :domain))))
               ;; Restoration retries the same logical record and acknowledges
               ;; broker acceptance; it does not mint another outbox entry.
               (hackmode:process-outbox-entry db reloaded transport :now 1012)
               (assert (eq :acknowledged (hackmode:outbox-entry-state reloaded)))
               (assert (eq :ingest-accepted (hackmode:outbox-entry-ack-kind reloaded)))
               (assert (= 202 (hackmode:outbox-entry-last-status reloaded)))
               (assert (= 2 (hackmode:outbox-entry-attempts reloaded)))
               (assert (= 1 (length (hackmode:list-outbox-entries db)))))))
           ;; Permanent 4xx is inspectable quarantine, never silently dropped.
           (let ((bad (make-instance 'hackmode:domain
                                     :record "bad.example"
                                     :record-type "A"
                                     :date-added 2000
                                     :date-updated 2000)))
             (multiple-value-bind (entry created-p)
                 (hackmode:enqueue-asset-for-starintel bad :database db :now 2000)
               (assert created-p)
               (hackmode:process-outbox-entry
                db entry (lambda (ignored)
                           (declare (ignore ignored))
                           (values 400 "invalid"))
                :now 2001)
               (assert (eq :quarantined (hackmode:outbox-entry-state entry)))
               (assert (= 1 (length (hackmode:list-outbox-entries
                                     db :state :quarantined))))))
           ;; Bounded retries eventually become FAILED and remain inspectable.
           (let ((hackmode:*outbox-max-attempts* 2)
                 (doomed (make-instance 'hackmode:domain
                                        :record "doomed.example"
                                        :record-type "A"
                                        :date-added 3000
                                        :date-updated 3000)))
             (multiple-value-bind (entry created-p)
                 (hackmode:enqueue-asset-for-starintel doomed :database db :now 3000)
               (assert created-p)
               (flet ((fail (ignored)
                        (declare (ignore ignored))
                        (error 'hackmode:outbox-transport-error :message "offline")))
                 (hackmode:process-outbox-entry db entry #'fail :now 3001)
                 (hackmode:process-outbox-entry db entry #'fail
                                                :now (hackmode:outbox-entry-next-attempt-at entry)))
               (assert (eq :failed (hackmode:outbox-entry-state entry)))))
           ;; Network delivery can run on a dedicated actor and return immediately.
           (let ((async-asset (make-instance 'hackmode:domain
                                             :record "async.example"
                                             :record-type "A"
                                             :date-added 4000
                                             :date-updated 4000)))
             (multiple-value-bind (entry created-p)
                 (hackmode:enqueue-asset-for-starintel async-asset :database db :now 4000)
               (assert created-p)
               (hackmode:start-outbox-actor
                :database db
                :transport (lambda (ignored)
                             (declare (ignore ignored))
                             (values 200 "accepted")))
               (hackmode:drain-outbox-async :now 4001 :limit 10)
               (assert
                (wait-until
                 (lambda ()
                   (eq :acknowledged
                       (hackmode:outbox-entry-state
                        (hackmode:fetch-outbox-entry
                         db (hackmode:outbox-entry-id entry))))))
                () "Async outbox actor did not acknowledge entry.")))
      (ignore-errors (hackmode:stop-hackmode-actor-system))
      (when (tek9:db-is-open-p db)
        (tek9:close-database db))
      (remove-test-path root))))

(defun run-tests ()
  (run-instance-state-test)
  (run-operation-registry-test)
  (run-starintel-projection-test)
  (run-asset-lifecycle-test)
  (run-outbox-lifecycle-test)
  (format t "Hackmode core tests passed.~%")
  t)
