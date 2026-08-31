(in-package :hackmode)

(eval-when (:load-toplevel :execute)
  (unless (fboundp '%expert-run-inspection-last-reason/raw)
    (setf (fdefinition '%expert-run-inspection-last-reason/raw)
          (fdefinition 'expert-run-inspection-last-reason))))

(defun expert-run-inspection-last-reason (inspection)
  "Return a defensive snapshot of INSPECTION's last reasoning reason."
  (check-type inspection expert-run-inspection)
  (%expert-inspection-copy
   (funcall (fdefinition '%expert-run-inspection-last-reason/raw)
            inspection)))
