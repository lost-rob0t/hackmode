(in-package :hackmode)

(uiop:define-package   :hackmode-user
  (:nicknames :hu)
  (:use       :hackmode)
  (:documentation "hackmode user envroment"))



(defun main ()
  (in-package :hackmode-user)
  (load hackmode-initfile)
  (nhooks:run-hook *startup-hook*))
