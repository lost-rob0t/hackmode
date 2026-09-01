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

           ;; Ingest-state views map canonical durable outbox records. Exercise
           ;; only public outbox APIs so this test fails on the view contract,
           ;; not package visibility or implementation details.
           (multiple-value-bind (queued queued-created-p)
               (hackmode:enqueue-starintel-json
                db
                (jsown:new-js
                  ("_id" "view-queued-doc")
                  ("dtype" "url"))
                :operation "op-views"
                :now 10)
             (assert queued-created-p () "Queued fixture must be created.")
             (multiple-value-bind (ack ack-created-p)
                 (hackmode:enqueue-starintel-json
                  db
                  (jsown:new-js
                    ("_id" "view-ack-doc")
                    ("dtype" "url"))
                  :operation "op-views"
                  :now 20)
               (assert ack-created-p () "Acknowledged fixture must be created.")
               (hackmode:process-outbox-entry
                db ack (lambda (entry)
                         (declare (ignore entry))
                         (values 202 "accepted"))
                :now 21)
               (hackmode:ensure-investigation-views db :rebuild t)
               (assert-equal (list (hackmode:outbox-entry-id queued))
                             (hackmode:investigation-view-outbox-ids
                              db :queued)
                             "ingest/by-state queued selection")
               (assert-equal (list (hackmode:outbox-entry-id ack))
                             (hackmode:investigation-view-outbox-ids
                              db :acknowledged)
                             "ingest/by-state acknowledged selection")

               ;; Re-enqueueing byte-identical evidence must not duplicate the row.
               (multiple-value-bind (repeat repeat-created-p)
                   (hackmode:enqueue-starintel-json
                    db
                    (jsown:new-js
                      ("_id" "view-queued-doc")
                      ("dtype" "url"))
                    :operation "op-views"
                    :now 30)
                 (assert (not repeat-created-p) ()
                         "Repeated outbox enqueue must remain idempotent.")
                 (assert-equal (hackmode:outbox-entry-id queued)
                               (hackmode:outbox-entry-id repeat)
                               "Repeated outbox entry identity"))

               (let ((before
                       (hackmode:investigation-view-rows
                        db :ingest-by-state)))
                 (hackmode:rebuild-investigation-views db)
                 (assert-equal before
                               (hackmode:investigation-view-rows
                                db :ingest-by-state)
                               "ingest/by-state rebuild equivalence"))))))
      (when (tek9:db-is-open-p db)
        (tek9:close-database db))
      (remove-test-path root)))
  t)
