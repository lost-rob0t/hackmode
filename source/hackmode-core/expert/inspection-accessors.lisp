(in-package :hackmode)

(defun expert-run-inspection-last-reason (inspection)
  "Return a defensive snapshot of INSPECTION's last reasoning reason."
  (check-type inspection expert-run-inspection)
  (%expert-inspection-copy
   (%expert-run-inspection-last-reason inspection)))
