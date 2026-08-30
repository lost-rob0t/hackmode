(in-package :hackmode-database-tests)

(defun run-effective-operational-kb-tests ()
  (let* ((path (merge-pathnames
                (format nil "hackmode-effective-kb-~D/" (random 1000000000))
                (uiop:temporary-directory)))
         (database (tek9:new-database "hackmode-effective-kb-test" :path path)))
    (unwind-protect
         (progn
           (tek9:open-database database)
           (let* ((first
                    (hackmode-database:make-operational-kb-assertion
                     :assertion-id "first"
                     :operation-id "op-1"
                     :run-id "run-1"
                     :expert-id "recon"
                     :expert-version "1"
                     :key '(:host "example.com")
                     :value '(:status :alive)
                     :evidence-ids '("evidence-1")
                     :provenance '(:source :fixture)))
                  (second
                    (hackmode-database:make-operational-kb-assertion
                     :assertion-id "second"
                     :operation-id "op-1"
                     :run-id "run-2"
                     :expert-id "recon"
                     :expert-version "1"
                     :key '(:service "example.com" 443)
                     :value '(:status :open)
                     :evidence-ids '("evidence-2")
                     :provenance '(:source :fixture)))
                  (retraction
                    (hackmode-database:make-operational-kb-retraction
                     :retraction-id "retract-first"
                     :operation-id "op-1"
                     :run-id "run-2"
                     :expert-id "recon"
                     :expert-version "1"
                     :target-assertion-id
                     (hackmode-database:operational-kb-entry-record-id first)
                     :evidence-ids '("evidence-3")
                     :provenance '(:source :fixture))))
             (hackmode-database:persist-operational-kb-entry database first)
             (hackmode-database:persist-operational-kb-entry database second)
             (hackmode-database:persist-operational-kb-entry database retraction)
             (let ((effective
                     (hackmode-database:fetch-effective-operational-kb-assertions
                      database "op-1")))
               (ensure (= 1 (length effective))
                       "effective snapshot did not remove the retracted assertion")
               (ensure (string=
                        (hackmode-database:operational-kb-entry-record-id second)
                        (hackmode-database:operational-kb-entry-record-id (first effective)))
                       "effective snapshot returned the wrong assertion"))
             (ensure
              (null (hackmode-database:fetch-effective-operational-kb-assertions
                     database "op-1" :run-id "run-1"))
              "run filtering resurrected an assertion retracted by a later run")
             (let ((run-2
                     (hackmode-database:fetch-effective-operational-kb-assertions
                      database "op-1" :run-id "run-2")))
               (ensure (= 1 (length run-2))
                       "run-filtered effective snapshot lost a live assertion")
               (ensure (string=
                        (hackmode-database:operational-kb-entry-record-id second)
                        (hackmode-database:operational-kb-entry-record-id (first run-2)))
                       "run-filtered effective snapshot returned the wrong assertion"))))
      (when (tek9:db-is-open-p database)
        (tek9:close-database database))
      (when (probe-file path)
        (uiop:delete-directory-tree path :validate t))))
  t)
