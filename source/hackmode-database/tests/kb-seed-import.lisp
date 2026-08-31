(in-package :hackmode-database-tests)

(defun run-kb-seed-import-tests ()
  (let* ((values '("admin" "login" "admin" "api/v1"))
         (assertions
           (make-operational-kb-seed-assertions
            :import-id "paths-2026-08"
            :operation-id "op-1"
            :run-id "run-9"
            :imported-by "seed-import"
            :importer-version "1"
            :seed-kind :wordlist
            :namespace "web-paths"
            :values values
            :evidence-ids '("artifact-wordlist-1")
            :provenance '(:source "fixture" :path "paths.txt")))
         (reordered
           (make-operational-kb-seed-assertions
            :import-id "paths-2026-08"
            :operation-id "op-1"
            :run-id "run-9"
            :imported-by "seed-import"
            :importer-version "1"
            :seed-kind :wordlist
            :namespace "web-paths"
            :values '("api/v1" "admin" "login")
            :evidence-ids '("artifact-wordlist-1")
            :provenance '(:source "fixture" :path "paths.txt"))))
    (ensure (= 3 (length assertions))
            "duplicate seed values were not collapsed")
    (ensure (equal (mapcar #'operational-kb-entry-record-id assertions)
                   (mapcar #'operational-kb-entry-record-id reordered))
            "seed import identity depends on input ordering")
    (dolist (assertion assertions)
      (ensure (eq :assert (operational-kb-entry-kind assertion))
              "seed import created a non-assertion record")
      (ensure (string= "op-1" (operational-kb-entry-operation-id assertion))
              "seed import lost operation scope")
      (ensure (string= "run-9" (operational-kb-entry-run-id assertion))
              "seed import lost run identity")
      (ensure (string= "seed-import" (operational-kb-entry-expert-id assertion))
              "seed import lost importer identity")
      (ensure (equal '(:seed :wordlist "web-paths")
                     (operational-kb-entry-key assertion))
              "seed import produced the wrong KB key")
      (ensure (equal '("artifact-wordlist-1")
                     (operational-kb-entry-evidence-ids assertion))
              "seed import lost evidence")
      (ensure (equal '(:source "fixture" :path "paths.txt")
                     (operational-kb-entry-provenance assertion))
              "seed import lost provenance"))
    (handler-case
        (progn
          (make-operational-kb-seed-assertions
           :import-id "bad"
           :operation-id "op-1"
           :run-id "run-9"
           :imported-by "seed-import"
           :importer-version "1"
           :seed-kind :credentials
           :namespace "oops"
           :values '("secret")
           :evidence-ids '("artifact-1")
           :provenance '(:source "fixture"))
          (error "unsupported seed kind was accepted"))
      (operational-kb-validation-error () t))
    (handler-case
        (progn
          (make-operational-kb-seed-assertions
           :import-id "bad-empty"
           :operation-id "op-1"
           :run-id "run-9"
           :imported-by "seed-import"
           :importer-version "1"
           :seed-kind :fuzz-list
           :namespace "payloads"
           :values '("ok" "")
           :evidence-ids '("artifact-1")
           :provenance '(:source "fixture"))
          (error "empty seed value was accepted"))
      (operational-kb-validation-error () t)))
  (let* ((path (merge-pathnames
                (format nil "hackmode-seed-atomic-~D/" (random 1000000000))
                (uiop:temporary-directory)))
         (database (tek9:new-database "hackmode-seed-atomic-test" :path path)))
    (unwind-protect
         (progn
           (tek9:open-database database)
           (let* ((arguments
                    (list :import-id "atomic-import"
                          :operation-id "op-atomic"
                          :run-id "run-atomic"
                          :imported-by "seed-import"
                          :importer-version "1"
                          :seed-kind :wordlist
                          :namespace "paths"
                          :values '("admin" "login")
                          :evidence-ids '("artifact-atomic")
                          :provenance '(:source "fixture")))
                  (assertions (apply #'make-operational-kb-seed-assertions arguments))
                  (admin (find "admin" assertions
                               :key #'operational-kb-entry-value :test #'string=))
                  (login (find "login" assertions
                               :key #'operational-kb-entry-value :test #'string=))
                  (conflict
                    (make-operational-kb-assertion
                     :assertion-id
                     (hackmode-database::%record-id
                      "operational-kb-seed" "atomic-import" "WORDLIST" "paths" "login")
                     :operation-id "op-atomic"
                     :run-id "run-atomic"
                     :expert-id "different-importer"
                     :expert-version "1"
                     :key '(:seed :wordlist "paths")
                     :value "login"
                     :evidence-ids '("artifact-conflict")
                     :provenance '(:source "conflict"))))
             (persist-operational-kb-entry database conflict)
             (handler-case
                 (progn
                   (apply #'persist-operational-kb-seed-values database arguments)
                   (error "conflicting seed import unexpectedly succeeded"))
               (persistence-replay-conflict () t))
             (ensure (null (fetch-operational-kb-entry
                            database "op-atomic"
                            (operational-kb-entry-record-id admin)))
                     "failed seed import left a partial canonical assertion")))
      (when (tek9:db-is-open-p database)
        (tek9:close-database database))
      (when (probe-file path)
        (uiop:delete-directory-tree path :validate t))))
  t)
