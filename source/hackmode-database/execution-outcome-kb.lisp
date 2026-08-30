(in-package :hackmode-database)

(defun make-execution-outcome-kb-candidate
    (&key call result expert-id expert-version provenance)
  "Build one operation-scoped KB assertion from typed execution evidence.

The candidate records only the capability, terminal status, and call identity.
Provider output remains in the execution graph and is referenced as evidence,
so this bridge does not copy potentially large or sensitive tool output into the
KB. Long-term promotion remains a separate explicit lifecycle decision."
  (validate-tool-result-link call result)
  (%kb-require-string :expert-id expert-id)
  (%kb-require-string :expert-version expert-version)
  (%kb-require-provenance provenance)
  (let* ((operation-id (execution-record-operation-id call))
         (run-id (execution-record-run-id call))
         (call-record-id (execution-record-record-id call))
         (result-record-id (execution-record-record-id result))
         (capability-id (execution-record-capability-id call))
         (status (execution-record-status result))
         (assertion-id (%record-id "execution-outcome-candidate"
                                   operation-id run-id call-record-id
                                   result-record-id capability-id status)))
    (make-operational-kb-assertion
     :assertion-id assertion-id
     :operation-id operation-id
     :run-id run-id
     :expert-id expert-id
     :expert-version expert-version
     :key (list :execution-outcome capability-id)
     :value (list :status status
                  :call-id (execution-record-call-id call))
     :evidence-ids (list call-record-id result-record-id)
     :provenance provenance)))
