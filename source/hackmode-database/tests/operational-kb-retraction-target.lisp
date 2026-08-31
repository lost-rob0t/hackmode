(in-package :hackmode-database-tests)

(defun run-operational-kb-retraction-target-tests ()
  (let* ((path (merge-pathnames
                (format nil "hackmode-kb-retraction-target-~D/"
                        (random 1000000000))
                (uiop:temporary-directory)))
         (database (tek9:new-database "hackmode-kb-retraction-target-test"
                                      :path path)))
    (unwind-protect
         (progn
           (tek9:open-database database)
           (let* ((operation-id "op-retraction-target")
                  (assertion
                    (make-operational-kb-assertion
                     :assertion-id "claim-1"
                     :operation-id operation-id
                     :run-id "run-1"
                     :expert-id "recon"
                     :expert-version "1"
                     :key '(:hypothesis "wildcard-dns")
                     :value '(:confidence 80)
                     :evidence-ids '("evidence-1")
                     :provenance '(:source "database-test")))
                  (target-id (operational-kb-entry-record-id assertion))
                  (graph-name (operational-kb-graph-name operation-id))
                  (retraction
                    (make-operational-kb-retraction
                     :retraction-id "retract-1"
                     :operation-id operation-id
                     :run-id "run-2"
                     :expert-id "recon"
                     :expert-version "1"
                     :target-assertion-id target-id
                     :evidence-ids '("evidence-2")
                     :provenance '(:source "database-test"))))
             ;; Simulate canonical graph corruption or a legacy/non-canonical writer:
             ;; an assertion-shaped stable ID exists, but the stored node is not an assertion.
             (tek9:put-node
              database
              (make-instance 'tek9:node
                             :id target-id
                             :props (list :kind :operational-kb-root
                                          :operation-id operation-id))
              :database-name graph-name)
             (handler-case
                 (progn
                   (persist-operational-kb-entry database retraction)
                   (error "retraction unexpectedly targeted a non-assertion node"))
               (operational-kb-validation-error () t))))
      (when (tek9:db-is-open-p database)
        (tek9:close-database database))
      (when (probe-file path)
        (uiop:delete-directory-tree path :validate t))))
  t)
