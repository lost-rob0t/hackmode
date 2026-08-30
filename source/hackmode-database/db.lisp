(in-package :hackmode-database)

(defvar *db* nil "The active Hackmode/Tek9 database object.")

(defun put-doc (document &key (database-name "std") (database *db*))
  "Persist DOCUMENT through the canonical Tek9 document boundary."
  (unless database
    (error "No Hackmode database is open."))
  (tek9:put* database document :database-name database-name))

(defun put-docs (documents &key (database-name "std") (database *db*))
  "Persist DOCUMENTS through one Tek9 bulk write."
  (unless database
    (error "No Hackmode database is open."))
  (tek9:put-bulk* database documents :database-name database-name))

(defun persist-execution-record (database record)
  "Persist one typed execution RECORD into its operation-scoped Tek9 graph."
  (persist-graph-node-replay-safe
   database
   (execution-record->tek9-node record)
   :database-name (execution-graph-name
                   (execution-record-operation-id record)))
  record)

(defun persist-tool-execution (database call result)
  "Persist CALL, RESULT, and their typed relation through Tek9's graph API."
  (validate-tool-result-link call result)
  (let ((graph-name (execution-graph-name (execution-record-operation-id call))))
    (tek9:with-write-transaction (database)
      (persist-graph-nodes-replay-safe
       database
       (list (execution-record->tek9-node call)
             (execution-record->tek9-node result))
       :database-name graph-name)
      (persist-graph-edge-replay-safe
       database
       (tool-result-link-edge call result)
       :database-name graph-name)))
  (values call result))

(defun fetch-operation-execution-records (database operation-id &key run-id kind)
  "Return typed execution records for one operation, optionally filtered by RUN-ID or KIND."
  (%require-string :operation-id operation-id)
  (when run-id
    (%require-string :run-id run-id))
  (when (and kind
             (not (member kind '(:tool-call :tool-result :http-exchange :capture-checkpoint)
                          :test #'eq)))
    (error 'execution-graph-validation-error
           :field :kind :value kind :reason "unsupported execution record filter"))
  (let ((records
          (loop for node in (tek9:fetch-graph-nodes
                             database (execution-graph-name operation-id))
                for record = (tek9-node->execution-record node)
                unless (string= operation-id (execution-record-operation-id record))
                  do (error 'execution-graph-validation-error
                            :field :operation-id
                            :value (execution-record-operation-id record)
                            :reason "stored record does not match graph operation scope")
                when (and (or (null run-id)
                              (string= run-id (execution-record-run-id record)))
                          (or (null kind)
                              (eq kind (execution-record-kind record))))
                  collect record)))
    (sort records #'string< :key #'execution-record-record-id)))

(defun fetch-latest-capture-checkpoint
    (database operation-id capture-session-id source-id)
  "Return the greatest durable checkpoint for one capture source, or NIL."
  (%require-string :operation-id operation-id)
  (%require-string :capture-session-id capture-session-id)
  (%require-string :source-id source-id)
  (let ((latest nil)
        (latest-offset nil))
    (dolist (record
             (fetch-operation-execution-records
              database operation-id
              :run-id capture-session-id
              :kind :capture-checkpoint))
      (when (string= source-id (execution-record-call-id record))
        (let ((offset (getf (execution-record-payload record) :offset)))
          (when (or (null latest-offset) (> offset latest-offset))
            (setf latest record
                  latest-offset offset)))))
    latest))

(defun persist-operational-kb-entry (database entry)
  "Persist one replay-safe operational KB assertion or retraction through Tek9."
  (let ((graph-name (operational-kb-graph-name
                     (operational-kb-entry-operation-id entry))))
    (tek9:with-write-transaction (database)
      (ecase (operational-kb-entry-kind entry)
        (:assert
         (persist-graph-nodes-replay-safe
          database
          (list (operational-kb-root-node
                 (operational-kb-entry-operation-id entry))
                (operational-kb-entry->tek9-node entry))
          :database-name graph-name)
         (persist-graph-edge-replay-safe
          database
          (operational-kb-membership-edge entry)
          :database-name graph-name))
        (:retract
         (unless (tek9:fetch-node database
                                  (operational-kb-entry-target-assertion-id entry)
                                  :database-name graph-name)
           (error 'operational-kb-validation-error
                  :field :target-assertion-id
                  :value (operational-kb-entry-target-assertion-id entry)
                  :reason "target assertion does not exist"))
         (persist-graph-node-replay-safe
          database
          (operational-kb-entry->tek9-node entry)
          :database-name graph-name)
         (persist-graph-edge-replay-safe
          database
          (operational-kb-retraction-edge entry)
          :database-name graph-name))))
    entry))

(defun fetch-operational-kb-entry (database operation-id record-id)
  "Fetch one operational KB graph node by stable RECORD-ID."
  (tek9:fetch-node database record-id
                   :database-name (operational-kb-graph-name operation-id)))

(defun fetch-operational-kb-entries (database operation-id &key run-id kind)
  "Return typed operational-KB entries for one operation, including retractions."
  (%kb-require-string :operation-id operation-id)
  (when run-id
    (%kb-require-string :run-id run-id))
  (when (and kind (not (member kind '(:assert :retract) :test #'eq)))
    (error 'operational-kb-validation-error
           :field :kind :value kind :reason "unsupported operational KB filter"))
  (let ((entries nil))
    (dolist (node (tek9:fetch-graph-nodes
                   database (operational-kb-graph-name operation-id)))
      (when (member (getf (tek9:node-props node) :kind)
                    '(:assert :retract) :test #'eq)
        (let ((entry (tek9-node->operational-kb-entry node)))
          (unless (string= operation-id (operational-kb-entry-operation-id entry))
            (error 'operational-kb-validation-error
                   :field :operation-id
                   :value (operational-kb-entry-operation-id entry)
                   :reason "stored entry does not match graph operation scope"))
          (when (and (or (null run-id)
                         (string= run-id (operational-kb-entry-run-id entry)))
                     (or (null kind)
                         (eq kind (operational-kb-entry-kind entry))))
            (push entry entries)))))
    (sort entries #'string< :key #'operational-kb-entry-record-id)))

(defun persist-long-term-kb-promotion (database promotion)
  "Persist one immutable evidence-backed promotion through canonical Tek9 graph APIs."
  (let ((graph-name (long-term-kb-graph-name)))
    (tek9:with-write-transaction (database)
      (persist-graph-nodes-replay-safe
       database
       (list (long-term-kb-root-node)
             (long-term-kb-source-reference-node promotion)
             (long-term-kb-promotion->tek9-node promotion))
       :database-name graph-name)
      (persist-graph-edges-replay-safe
       database
       (list (long-term-kb-membership-edge promotion)
             (long-term-kb-source-edge promotion))
       :database-name graph-name)))
  promotion)

(defun fetch-long-term-kb-promotion (database record-id)
  "Fetch one long-term KB promotion by its stable record identity."
  (tek9:fetch-node database record-id
                   :database-name (long-term-kb-graph-name)))

(defun fetch-long-term-kb-promotions (database &key source-operation-id)
  "Return typed long-term KB promotions in deterministic record-ID order."
  (when source-operation-id
    (%long-term-require-string :source-operation-id source-operation-id))
  (let ((promotions nil))
    (dolist (node (tek9:fetch-graph-nodes database (long-term-kb-graph-name)))
      (when (eq :long-term-kb-promotion (getf (tek9:node-props node) :kind))
        (let ((promotion (tek9-node->long-term-kb-promotion node)))
          (when (or (null source-operation-id)
                    (string= source-operation-id
                             (long-term-kb-promotion-source-operation-id promotion)))
            (push promotion promotions)))))
    (sort promotions #'string< :key #'long-term-kb-promotion-record-id)))

(defun persist-global-kb-export (database export)
  "Persist one explicit immutable export through canonical Tek9 graph APIs."
  (let ((graph-name (global-kb-graph-name)))
    (tek9:with-write-transaction (database)
      (persist-graph-nodes-replay-safe
       database
       (list (global-kb-root-node)
             (global-kb-source-reference-node export)
             (global-kb-export->tek9-node export))
       :database-name graph-name)
      (persist-graph-edges-replay-safe
       database
       (list (global-kb-membership-edge export)
             (global-kb-source-edge export))
       :database-name graph-name)))
  export)

(defun fetch-global-kb-export (database record-id)
  "Fetch one explicit global KB export by stable record identity."
  (tek9:fetch-node database record-id
                   :database-name (global-kb-graph-name)))

(defun fetch-global-kb-exports (database &key source-operation-id)
  "Return typed global KB exports in deterministic record-ID order."
  (when source-operation-id
    (%global-require-string :source-operation-id source-operation-id))
  (let ((exports nil))
    (dolist (node (tek9:fetch-graph-nodes database (global-kb-graph-name)))
      (when (eq :global-kb-export (getf (tek9:node-props node) :kind))
        (let ((export (tek9-node->global-kb-export node)))
          (when (or (null source-operation-id)
                    (string= source-operation-id
                             (global-kb-export-source-operation-id export)))
            (push export exports)))))
    (sort exports #'string< :key #'global-kb-export-record-id)))
