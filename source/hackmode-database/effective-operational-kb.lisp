(in-package :hackmode-database)

(defun fetch-effective-operational-kb-assertions
    (database operation-id &key run-id)
  "Return live operational-KB assertions after resolving all canonical retractions.

Retractions are resolved across the whole operation before RUN-ID filters the
remaining assertions. This prevents a later run from retracting an assertion and
a filtered read from accidentally resurrecting it."
  (%kb-require-string :operation-id operation-id)
  (when run-id
    (%kb-require-string :run-id run-id))
  (let* ((entries (fetch-operational-kb-entries database operation-id))
         (assertions (make-hash-table :test #'equal))
         (retracted (make-hash-table :test #'equal)))
    (dolist (entry entries)
      (when (eq :assert (operational-kb-entry-kind entry))
        (setf (gethash (operational-kb-entry-record-id entry) assertions)
              entry)))
    (dolist (entry entries)
      (when (eq :retract (operational-kb-entry-kind entry))
        (let ((target-id (operational-kb-entry-target-assertion-id entry)))
          (unless (gethash target-id assertions)
            (error 'operational-kb-validation-error
                   :field :target-assertion-id
                   :value target-id
                   :reason "stored retraction target assertion is missing"))
          (setf (gethash target-id retracted) t))))
    (loop for entry in entries
          when (and (eq :assert (operational-kb-entry-kind entry))
                    (not (gethash (operational-kb-entry-record-id entry)
                                  retracted))
                    (or (null run-id)
                        (string= run-id
                                 (operational-kb-entry-run-id entry))))
            collect entry)))
