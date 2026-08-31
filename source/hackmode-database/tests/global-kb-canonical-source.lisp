(in-package :hackmode-database-tests)

(defun run-global-kb-canonical-source-tests ()
  (let* ((path (merge-pathnames
                (format nil "hackmode-global-canonical-source-~D/"
                        (random 1000000000))
                (uiop:temporary-directory)))
         (database (tek9:new-database "hackmode-global-canonical-source-test"
                                      :path path)))
    (unwind-protect
         (progn
           (tek9:open-database database)
           (let* ((source
                    (make-operational-kb-assertion
                     :assertion-id "a-global-canonical"
                     :operation-id "op-global-canonical"
                     :run-id "run-1"
                     :expert-id "recon"
                     :expert-version "1"
                     :key '(:service "https")
                     :value '(:port 443)
                     :evidence-ids '("result-global-canonical")
                     :provenance '(:source "fixture")))
                  (promotion
                    (make-long-term-kb-promotion
                     :promotion-id "p-global-canonical"
                     :source-assertion source
                     :promoted-by "operator"
                     :promoter-version "1"
                     :evidence-ids '("review-global-canonical")
                     :provenance '(:reason "validated")))
                  (export
                    (make-global-kb-export
                     :export-id "e-global-canonical"
                     :source-promotion promotion
                     :exported-by "operator"
                     :exporter-version "1"
                     :evidence-ids '("approval-global-canonical")
                     :provenance '(:reason "explicit export"))))
             (persist-operational-kb-entry database source)
             (handler-case
                 (progn
                   (persist-global-kb-export database export)
                   (error "non-canonical long-term promotion unexpectedly exported"))
               (global-kb-validation-error () t))
             (persist-long-term-kb-promotion database promotion)
             (persist-global-kb-export database export)
             (ensure (tek9:fetch-node
                      database
                      (global-kb-export-record-id export)
                      :database-name (global-kb-graph-name))
                     "canonical long-term promotion was not exportable")))
      (when (tek9:db-is-open-p database)
        (tek9:close-database database))
      (when (probe-file path)
        (uiop:delete-directory-tree path :validate t))))
  t)
