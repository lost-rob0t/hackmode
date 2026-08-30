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
  (tek9:put-node database
                 (execution-record->tek9-node record)
                 :database-name (execution-graph-name
                                 (execution-record-operation-id record)))
  record)

(defun persist-tool-execution (database call result)
  "Persist CALL, RESULT, and their typed relation through Tek9's graph API."
  (validate-tool-result-link call result)
  (let ((graph-name (execution-graph-name (execution-record-operation-id call))))
    (tek9:put-nodes database
                    (list (execution-record->tek9-node call)
                          (execution-record->tek9-node result))
                    :database-name graph-name)
    (tek9:put-edge database
                   (tool-result-link-edge call result)
                   :database-name graph-name))
  (values call result))
