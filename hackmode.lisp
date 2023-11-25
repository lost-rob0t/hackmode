(defpackage   :hackmode-user
  (:export :main)
  (:use :cl #:hackmode)
  (:documentation "top level entry function"))
;; I dont really use hackmode-user
(in-package :hackmode-user)

(defun main ()
  (in-package :cl-user)
  (use-package :hackmode)
  (use-package :hackmode-tools)
  (load hackmode-init-file)
  (nhooks:run-hook *startup-hook*)
  (lish:lish))
