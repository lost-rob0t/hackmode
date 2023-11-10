(in-package :hackmode)

(defmethod run ((exploit exploit))
  (funcall (exploit-func exploit))
  (nhooks:run-hook '*history-hook* (make-history-entry run (exploit-name exploit))))


(defun* (use -> exploit ) ((name string))
  "Set *current-package* to name of package"
  (setq *current-package* (@ *exploits* name)))
