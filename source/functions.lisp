(in-package :hackmode)
(defmethod run ((exploit exploit))
  (funcall (exploit-func exploit))
  (nhooks:run-hook '*history-hook* (make-history-entry run (exploit-name exploit))))


(defmethod use ((exploit exploit))
  (setq *current-package* exploit))
