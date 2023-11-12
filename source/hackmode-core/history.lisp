(in-package :hackmode)

(defclass history ()
  ((path :initarg :path :initform history-path :accessor history-path)
   (entries :initarg :history-entries :accessor history-entries :initform nil)))


(defclass history-entry ()
  ((time :initarg :time :initform (local-time:timestamp-to-unix (local-time:now) ) :reader history-time)
   (command :initarg :command :initform (error 'invalid-object-error :slot :commmand) :reader history-command)))
