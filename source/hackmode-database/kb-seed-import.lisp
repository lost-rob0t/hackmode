(in-package :hackmode-database)

(defparameter +operational-kb-seed-import-limit+ 10000
  "Maximum number of raw values admitted by one operational KB seed import.")

(defparameter +operational-kb-seed-kinds+ '(:wordlist :fuzz-list)
  "Seed-list kinds accepted by the operational KB import boundary.")

(defun %require-seed-kind (seed-kind)
  (unless (member seed-kind +operational-kb-seed-kinds+ :test #'eq)
    (error 'operational-kb-validation-error
           :field :seed-kind
           :value seed-kind
           :reason "expected :WORDLIST or :FUZZ-LIST"))
  seed-kind)

(defun %require-seed-values (values)
  (unless (listp values)
    (error 'operational-kb-validation-error
           :field :values
           :value values
           :reason "expected a list of non-empty strings"))
  (when (> (length values) +operational-kb-seed-import-limit+)
    (error 'operational-kb-validation-error
           :field :values
           :value (length values)
           :reason "seed import exceeds the configured value limit"))
  (unless (and values (every #'%non-empty-string-p values))
    (error 'operational-kb-validation-error
           :field :values
           :value values
           :reason "expected at least one non-empty string"))
  values)

(defun %canonical-seed-values (values)
  (sort (remove-duplicates (copy-list values) :test #'string=) #'string<))

(defun make-operational-kb-seed-assertions
    (&key import-id operation-id run-id imported-by importer-version
          seed-kind namespace values evidence-ids provenance)
  "Build deterministic operational-KB assertions from a bounded seed list.

Seed imports are operation-local working knowledge. This constructor never
promotes entries into long-term or global KB scopes. Duplicate string values
collapse and input ordering cannot change logical record identity."
  (%kb-require-string :import-id import-id)
  (%kb-require-string :operation-id operation-id)
  (%kb-require-string :run-id run-id)
  (%kb-require-string :imported-by imported-by)
  (%kb-require-string :importer-version importer-version)
  (%require-seed-kind seed-kind)
  (%kb-require-string :namespace namespace)
  (%require-seed-values values)
  (%kb-require-evidence evidence-ids)
  (%kb-require-provenance provenance)
  (loop for value in (%canonical-seed-values values)
        for assertion-id = (%record-id "operational-kb-seed"
                                      import-id
                                      (symbol-name seed-kind)
                                      namespace
                                      value)
        collect
        (make-operational-kb-assertion
         :assertion-id assertion-id
         :operation-id operation-id
         :run-id run-id
         :expert-id imported-by
         :expert-version importer-version
         :key (list :seed seed-kind namespace)
         :value value
         :evidence-ids evidence-ids
         :provenance provenance)))

(defun persist-operational-kb-seed-values
    (database &rest arguments &key &allow-other-keys)
  "Atomically persist one bounded seed-list import into operational KB.

All assertions share one canonical Tek9 write transaction. A replay conflict
therefore aborts the whole import instead of leaving a partially imported list."
  (let* ((assertions (apply #'make-operational-kb-seed-assertions arguments))
         (operation-id (operational-kb-entry-operation-id (first assertions)))
         (graph-name (operational-kb-graph-name operation-id)))
    (tek9:with-write-transaction (database)
      (persist-graph-node-replay-safe
       database (operational-kb-root-node operation-id)
       :database-name graph-name)
      (dolist (assertion assertions)
        (persist-graph-node-replay-safe
         database (operational-kb-entry->tek9-node assertion)
         :database-name graph-name)
        (persist-graph-edge-replay-safe
         database (operational-kb-membership-edge assertion)
         :database-name graph-name)))
    assertions))
