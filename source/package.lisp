(uiop:define-package :hackmode
  (:use :cl)
  (:use :defstar)
  (:import-from :serapeum :dict)
  (:documentation "Core hackmode internalls."))


(in-package :hackmode)
(setq *check-argument-types-explicitly?* t)
