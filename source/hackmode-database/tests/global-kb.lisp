(in-package :hackmode-database-tests)

(defun run-global-kb-tests ()
  (let* ((source
           (make-operational-kb-assertion
            :assertion-id "a-global"
            :operation-id "op-global"
            :run-id "run-global"
            :expert-id "recon"
            :expert-version "1"
            :key '(:service-pattern "nginx")
            :value '(:stable t)
            :evidence-ids '("call-global" "result-global")
            :provenance '(:source "fixture")))
         (promotion
           (make-long-term-kb-promotion
            :promotion-id "p-global"
            :source-assertion source
            :promoted-by "operator-policy"
            :promoter-version "1"
            :evidence-ids '("review-global")
            :provenance '(:reason "validated reusable pattern")))
         (export
           (make-global-kb-export
            :export-id "export-1"
            :source-promotion promotion
            :exported-by "operator"
            :exporter-version "1"
            :evidence-ids '("approval-global")
            :provenance '(:reason "explicit loot")))
         (same
           (make-global-kb-export
            :export-id "export-1"
            :source-promotion promotion
            :exported-by "operator"
            :exporter-version "1"
            :evidence-ids '("approval-global")
            :provenance '(:reason "explicit loot"))))
    (ensure (string= (global-kb-export-record-id export)
                     (global-kb-export-record-id same))
            "replaying global export changed its identity")
    (ensure (string= (long-term-kb-promotion-record-id promotion)
                     (global-kb-export-source-promotion-id export))
            "global export lost source promotion identity")
    (ensure (string= "op-global"
                     (global-kb-export-source-operation-id export))
            "global export lost source operation provenance")
    (ensure (equal (long-term-kb-promotion-key promotion)
                   (global-kb-export-key export))
            "global export key drifted from long-term promotion")
    (ensure (equal (long-term-kb-promotion-value promotion)
                   (global-kb-export-value export))
            "global export value drifted from long-term promotion")
    (ensure (equal '("approval-global")
                   (global-kb-export-evidence-ids export))
            "global export lost explicit export evidence")
    (let ((edge (global-kb-source-edge export)))
      (ensure (string= (global-kb-export-record-id export)
                       (tek9:edge-source edge))
              "global source edge has wrong source")
      (ensure (string= (long-term-kb-promotion-record-id promotion)
                       (tek9:edge-target edge))
              "global source edge lost exact long-term promotion"))
    (handler-case
        (progn
          (make-global-kb-export
           :export-id "export-no-evidence"
           :source-promotion promotion
           :exported-by "operator"
           :exporter-version "1"
           :evidence-ids nil
           :provenance '(:reason "invalid"))
          (error "global export unexpectedly accepted without evidence"))
      (global-kb-validation-error () t)))
  (let* ((path (merge-pathnames
                (format nil "hackmode-global-read-~D/" (random 1000000000))
                (uiop:temporary-directory)))
         (database (tek9:new-database "hackmode-global-read-test" :path path)))
    (unwind-protect
         (progn
           (tek9:open-database database)
           (flet ((source (operation assertion)
                    (make-operational-kb-assertion
                     :assertion-id assertion
                     :operation-id operation
                     :run-id "run-1"
                     :expert-id "recon"
                     :expert-version "1"
                     :key (list :operation operation)
                     :value '(:validated t)
                     :evidence-ids (list (format nil "result-~A" operation))
                     :provenance '(:source "fixture"))))
             (let* ((source-a (source "op-a" "a-a"))
                    (source-b (source "op-b" "a-b"))
                    (promotion-a
                      (make-long-term-kb-promotion
                       :promotion-id "p-a"
                       :source-assertion source-a
                       :promoted-by "operator"
                       :promoter-version "1"
                       :evidence-ids '("review-op-a")
                       :provenance '(:reason "reusable")))
                    (promotion-b
                      (make-long-term-kb-promotion
                       :promotion-id "p-b"
                       :source-assertion source-b
                       :promoted-by "operator"
                       :promoter-version "1"
                       :evidence-ids '("review-op-b")
                       :provenance '(:reason "reusable")))
                    (export-b
                      (make-global-kb-export
                       :export-id "e-b"
                       :source-promotion promotion-b
                       :exported-by "operator"
                       :exporter-version "1"
                       :evidence-ids '("approval-b")
                       :provenance '(:reason "shared")))
                    (export-a
                      (make-global-kb-export
                       :export-id "e-a"
                       :source-promotion promotion-a
                       :exported-by "operator"
                       :exporter-version "1"
                       :evidence-ids '("approval-a")
                       :provenance '(:reason "shared"))))
               (persist-operational-kb-entry database source-a)
               (persist-operational-kb-entry database source-b)
               (persist-long-term-kb-promotion database promotion-b)
               (persist-long-term-kb-promotion database promotion-a)
               (persist-global-kb-export database export-b)
               (persist-global-kb-export database export-a)
               (let ((fetched (fetch-global-kb-export
                               database (global-kb-export-record-id export-a))))
                 (ensure (typep fetched 'global-kb-export)
                         "singular global KB fetch leaked a raw Tek9 node")
                 (ensure (string= (global-kb-export-record-id export-a)
                                  (global-kb-export-record-id fetched))
                         "singular global KB fetch changed stable identity")
                 (ensure (equal '("approval-a")
                                (global-kb-export-evidence-ids fetched))
                         "singular global KB fetch lost export evidence")
                 (ensure (null (fetch-global-kb-export database "missing-export"))
                         "singular global KB fetch should return NIL when absent"))
               (let ((all (fetch-global-kb-exports database))
                     (op-a (fetch-global-kb-exports
                            database :source-operation-id "op-a")))
                 (ensure (= 2 (length all))
                         "global KB enumeration lost exports")
                 (ensure (every (lambda (item) (typep item 'global-kb-export)) all)
                         "global KB enumeration leaked raw Tek9 nodes")
                 (ensure (equal (sort (mapcar #'global-kb-export-record-id
                                             (copy-list all))
                                      #'string<)
                                (mapcar #'global-kb-export-record-id all))
                         "global KB enumeration is not deterministic")
                 (ensure (= 1 (length op-a))
                         "global KB operation filter returned wrong count")
                 (ensure (string= "op-a"
                                  (global-kb-export-source-operation-id
                                   (first op-a)))
                         "global KB operation filter leaked another operation")
                 (ensure (equal '("approval-a")
                                (global-kb-export-evidence-ids (first op-a)))
                         "global KB read lost export evidence provenance")))))
      (when (tek9:db-is-open-p database)
        (tek9:close-database database))
      (when (probe-file path)
        (uiop:delete-directory-tree path :validate t))))
  t)
