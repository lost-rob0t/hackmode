(in-package :hackmode-tests)

(defun run-investigation-view-tests ()
  (let* ((root (fresh-test-path "hackmode-investigation-views"))
         (db (tek9:new-database "investigation-views" :path root)))
    (unwind-protect
         (progn
           (tek9:open-database db)
           (hackmode:ensure-investigation-views db)

           (multiple-value-bind (first created-p)
               (hackmode:discover-asset
                (make-instance 'hackmode:domain
                               :record "alpha.example"
                               :record-type "A"
                               :operation "op-views"
                               :tags '("external" "api"))
                :database db
                :publish nil)
             (declare (ignore first))
             (assert created-p () "First asset discovery must create the asset."))

           (hackmode:discover-asset
            (make-instance 'hackmode:domain
                           :record "beta.example"
                           :record-type "A"
                           :operation "op-views"
                           :tags '("external"))
            :database db
            :publish nil)

           (hackmode:discover-asset
            (make-instance 'hackmode:url
                           :scheme "https"
                           :host "alpha.example"
                           :port 443
                           :path "/api"
                           :operation "op-views"
                           :tags '("api"))
            :database db
            :publish nil)

           (let ((domain-ids
                   (hackmode:investigation-view-asset-ids
                    db :by-type "domain"))
                 (api-ids
                   (hackmode:investigation-view-asset-ids
                    db :by-tag "api"))
                 (external-ids
                   (hackmode:investigation-view-asset-ids
                    db :by-tag "external")))
             (assert-equal 2 (length domain-ids) "assets/by-type domain count")
             (assert-equal 2 (length api-ids) "assets/by-tag api count")
             (assert-equal 2 (length external-ids) "assets/by-tag external count")
             (assert-equal domain-ids
                           (sort (copy-list domain-ids) #'string<)
                           "stable domain row order")

             ;; Re-discovery is idempotent and must not create a second view row.
             (multiple-value-bind (repeat repeat-created-p)
                 (hackmode:discover-asset
                  (make-instance 'hackmode:domain
                                 :record "alpha.example"
                                 :record-type "A"
                                 :operation "op-views"
                                 :tags '("external" "api"))
                  :database db
                  :publish nil)
               (declare (ignore repeat))
               (assert (not repeat-created-p) ()
                       "Repeated discovery must remain idempotent."))
             (assert-equal domain-ids
                           (hackmode:investigation-view-asset-ids
                            db :by-type "domain")
                           "repeated discovery view identity")

             ;; A full rebuild must be equivalent to the incrementally maintained rows.
             (let ((before-type
                     (hackmode:investigation-view-rows db :by-type))
                   (before-tag
                     (hackmode:investigation-view-rows db :by-tag)))
               (hackmode:rebuild-investigation-views db)
               (assert-equal before-type
                             (hackmode:investigation-view-rows db :by-type)
                             "assets/by-type rebuild equivalence")
               (assert-equal before-tag
                             (hackmode:investigation-view-rows db :by-tag)
                             "assets/by-tag rebuild equivalence")))

           ;; Ingest-state views must map canonical durable outbox records rather
           ;; than duplicating state into the primary operation database.
           (let* ((queued
                    (make-instance 'hackmode:outbox-entry
                                   :id "outbox-queued"
                                   :document-id "doc-queued"
                                   :dtype "url"
                                   :operation "op-views"
                                   :payload "{}"
                                   :state :queued
                                   :created-at 10
                                   :updated-at 10))
                  (failed
                    (make-instance 'hackmode:outbox-entry
                                   :id "outbox-failed"
                                   :document-id "doc-failed"
                                   :dtype "url"
                                   :operation "op-views"
                                   :payload "{}"
                                   :state :failed
                                   :created-at 20
                                   :updated-at 20)))
             (hackmode:persist-outbox-entry db queued)
             (hackmode:persist-outbox-entry db failed)
             (hackmode:ensure-investigation-views db :rebuild t)
             (assert-equal '("outbox-queued")
                           (hackmode:investigation-view-outbox-ids
                            db :queued)
                           "ingest/by-state queued selection")
             (assert-equal '("outbox-failed")
                           (hackmode:investigation-view-outbox-ids
                            db :failed)
                           "ingest/by-state failed selection")
             (let ((before
                     (hackmode:investigation-view-rows
                      db :ingest-by-state)))
               (hackmode:rebuild-investigation-views db)
               (assert-equal before
                             (hackmode:investigation-view-rows
                              db :ingest-by-state)
                             "ingest/by-state rebuild equivalence"))))
      (when (tek9:db-is-open-p db)
        (tek9:close-database db))
      (remove-test-path root)))
  t)
