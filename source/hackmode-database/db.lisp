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

(defun persist-long-term-kb-promotion (database promotion)
  "Persist one immutable evidence-backed promotion through canonical Tek9 graph APIs."
  (let ((graph-name (long-term-kb-graph-name)))
    (tek9:with-write-transaction (database)
      (persist-graph-nodes-replay-safe
       database
       (list (long-term-kb-root-node)
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

(defun persist-global-kb-export (database export)
  "Persist one explicit immutable export through canonical Tek9 graph APIs."
  (let ((graph-name (global-kb-graph-name)))
    (tek9:with-write-transaction (database)
      (persist-graph-nodes-replay-safe
       database
       (list (global-kb-root-node)
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
