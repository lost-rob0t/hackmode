(in-package :hackmode)

(defstruct (expert-budget-inspection-state
             (:constructor %make-expert-budget-inspection-state
                 (&key objective-id objective-version operation run-id
                       raw-entries exhausted-p)))
  "Pure operator-facing snapshot of one run-scoped objective budget."
  (objective-id nil :read-only t)
  (objective-version nil :read-only t)
  (operation nil :read-only t)
  (run-id nil :read-only t)
  (raw-entries nil :read-only t)
  (exhausted-p nil :read-only t))

(defun copy-expert-budget-inspection-entry (entry)
  (list :name (copy-seq (getf entry :name))
        :limit (getf entry :limit)
        :used (getf entry :used)
        :remaining (getf entry :remaining)
        :exhausted (getf entry :exhausted)))

(defun expert-budget-inspection (state)
  "Return deterministic, side-effect-free operator budget metadata for STATE."
  (check-type state expert-budget-state)
  (let ((entries
          (sort
           (mapcar
            (lambda (limit)
              (let* ((name (car limit))
                     (maximum (cdr limit))
                     (used (expert-budget-used state name))
                     (remaining (- maximum used)))
                (list :name (copy-seq name)
                      :limit maximum
                      :used used
                      :remaining remaining
                      :exhausted (zerop remaining))))
            (expert-budget-state-raw-limits state))
           #'string< :key (lambda (entry) (getf entry :name)))))
    (%make-expert-budget-inspection-state
     :objective-id (copy-seq (expert-budget-state-objective-id state))
     :objective-version (copy-seq (expert-budget-state-objective-version state))
     :operation (copy-seq (expert-budget-state-operation state))
     :run-id (copy-seq (expert-budget-state-run-id state))
     :raw-entries entries
     :exhausted-p (some (lambda (entry) (getf entry :exhausted)) entries))))

(defun expert-budget-inspection-objective-id (inspection)
  (copy-seq (expert-budget-inspection-state-objective-id inspection)))

(defun expert-budget-inspection-objective-version (inspection)
  (copy-seq (expert-budget-inspection-state-objective-version inspection)))

(defun expert-budget-inspection-operation (inspection)
  (copy-seq (expert-budget-inspection-state-operation inspection)))

(defun expert-budget-inspection-run-id (inspection)
  (copy-seq (expert-budget-inspection-state-run-id inspection)))

(defun expert-budget-inspection-entries (inspection)
  (mapcar #'copy-expert-budget-inspection-entry
          (expert-budget-inspection-state-raw-entries inspection)))

(defun expert-budget-inspection-exhausted-p (inspection)
  (expert-budget-inspection-state-exhausted-p inspection))

(export '(expert-budget-inspection
          expert-budget-inspection-objective-id
          expert-budget-inspection-objective-version
          expert-budget-inspection-operation
          expert-budget-inspection-run-id
          expert-budget-inspection-entries
          expert-budget-inspection-exhausted-p))
