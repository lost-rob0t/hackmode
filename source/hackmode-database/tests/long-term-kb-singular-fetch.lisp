(in-package :hackmode-database-tests)

(defun run-long-term-kb-singular-fetch-tests ()
  (let* ((path (merge-pathnames
                (format nil "hackmode-long-term-singular-~D/" (random 1000000000))
                (uiop:temporary-directory)))
         (database (tek9:new-database "hackmode-long-term-singular-test" :path path)))
    (unwind-protect
         (progn
           (tek9:open-database database)
           (let* ((source
                    (make-operational-kb-assertion
                     :assertion-id "a-singular"
                     :operation-id "op-singular"
                     :run-id "run-1"
                     :expert-id "recon"
                     :expert-version "1"
                     :key '(:service "https")
                     :value '(:port 443)
                     :evidence-ids '("result-singular")
                     :provenance '(:source "fixture")))
                  (promotion
                    (make-long-term-kb-promotion
                     :promotion-id "p-singular"
                     :source-assertion source
                     :promoted-by "operator"
                     :promoter-version "1"
                     :evidence-ids '("review-singular")
                     :provenance '(:reason "validated"))))
             (persist-operational-kb-entry database source)
             (persist-long-term-kb-promotion database promotion)
             (let ((fetched
                     (fetch-long-term-kb-promotion
                      database
                      (long-term-kb-promotion-record-id promotion))))
               (ensure (typep fetched 'long-term-kb-promotion)
                       "singular long-term KB fetch leaked a raw Tek9 node")
               (ensure (string=
                        (long-term-kb-promotion-record-id promotion)
                        (long-term-kb-promotion-record-id fetched))
                       "singular long-term KB fetch changed promotion identity")
               (ensure (equal '("result-singular")
                              (long-term-kb-promotion-source-evidence-ids fetched))
                       "singular long-term KB fetch lost source evidence"))
             (ensure (null (fetch-long-term-kb-promotion database "missing-promotion"))
                     "missing singular long-term KB fetch did not return NIL")))
      (when (tek9:db-is-open-p database)
        (tek9:close-database database))
      (when (probe-file path)
        (uiop:delete-directory-tree path :validate t))))
  t)
