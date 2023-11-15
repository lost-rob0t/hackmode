(in-package :hackmode)

;; (defvar* (*history* list) (list) "The history object.")
;; (defvar* (*last-command*  string) "" "The last command that was ran.")

;; (defclass history ()
;;   ((path :initarg :path :initform history-path :accessor history-path)
;;    (entries :initarg :history-entries :accessor history-entries :initform nil)))


;; (defclass history-entry ()
;;   ((time :initarg :time :initform (unix-now) :reader history-time)
;;    (command :initarg :command :initform (error "Missing Slot: History Entry requires the command slot.") :reader history-command)))


;; (defun make-history (command)
;;   "Create a history-entry object."
;;   (make-instance 'history-entry  :command command))
