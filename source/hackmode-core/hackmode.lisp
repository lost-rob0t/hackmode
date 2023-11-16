(in-package :hackmode)

(uiop:define-package   :hackmode-user
  (:nicknames :hu)
  (:use       :hackmode)
  (:documentation "hackmode user envroment"))



(defun main ()
  (in-package :hackmode-user)
  (load hackmode hackmode-init-file)
  (nhooks:run-hook *startup-hook*))
