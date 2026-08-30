(in-package :hackmode)

(defvar *base-expert-snapshot-function* (symbol-function 'expert-snapshot)
  "Base snapshot projector before graph/KB state projection is layered on.")

(defun expert-data-string (value)
  "Return a deterministic printable representation for typed snapshot data."
  (cond
    ((null value) "")
    ((stringp value) value)
    ((symbolp value) (string-downcase (symbol-name value)))
    (t (with-output-to-string (stream)
         (let ((*print-readably* t)
               (*print-pretty* nil))
           (prin1 value stream))))))

(defun expert-write-execution-record-fact (stream record)
  (write-expert-fact
   stream
   "execution_record"
   (hack-db:execution-record-record-id record)
   (expert-data-string (hack-db:execution-record-kind record))
   (hack-db:execution-record-operation-id record)
   (hack-db:execution-record-run-id record)
   (hack-db:execution-record-call-id record)
   (expert-data-string (hack-db:execution-record-capability-id record))
   (expert-data-string (hack-db:execution-record-status record))
   (expert-data-string (hack-db:execution-record-payload record))
   (expert-data-string (hack-db:execution-record-provenance record))))

(defun expert-write-operational-kb-entry-fact (stream entry)
  (write-expert-fact
   stream
   "operational_kb_entry"
   (hack-db:operational-kb-entry-record-id entry)
   (expert-data-string (hack-db:operational-kb-entry-kind entry))
   (hack-db:operational-kb-entry-operation-id entry)
   (hack-db:operational-kb-entry-run-id entry)
   (hack-db:operational-kb-entry-expert-id entry)
   (hack-db:operational-kb-entry-expert-version entry)
   (expert-data-string (hack-db:operational-kb-entry-key entry))
   (expert-data-string (hack-db:operational-kb-entry-value entry))
   (expert-data-string (hack-db:operational-kb-entry-target-assertion-id entry))
   (expert-data-string (hack-db:operational-kb-entry-evidence-ids entry))
   (expert-data-string (hack-db:operational-kb-entry-provenance entry))))

(defun expert-state-facts (execution-records operational-kb-entries)
  "Project typed canonical execution/operational-KB records into Prolog facts."
  (with-output-to-string (stream)
    (dolist (record
             (sort (copy-list execution-records) #'string<
                   :key #'hack-db:execution-record-record-id))
      (check-type record hack-db:execution-record)
      (expert-write-execution-record-fact stream record))
    (dolist (entry
             (sort (copy-list operational-kb-entries) #'string<
                   :key #'hack-db:operational-kb-entry-record-id))
      (check-type entry hack-db:operational-kb-entry)
      (expert-write-operational-kb-entry-fact stream entry))))

(defun expert-snapshot (&key
                          (operation (current-operation))
                          (assets (expert-current-assets))
                          (providers (list-capability-providers))
                          query-target
                          query-asset
                          execution-records
                          operational-kb-entries)
  "Return a deterministic expert snapshot including typed execution/KB state.

EXECUTION-RECORDS and OPERATIONAL-KB-ENTRIES must come from Hackmode's canonical
database boundary. This function only projects supplied typed records; it does
not enumerate storage, persist data, dispatch providers, or widen authority."
  (concatenate
   'string
   (funcall *base-expert-snapshot-function*
            :operation operation
            :assets assets
            :providers providers
            :query-target query-target
            :query-asset query-asset)
   (expert-state-facts execution-records operational-kb-entries)))

(export '(expert-state-facts))
