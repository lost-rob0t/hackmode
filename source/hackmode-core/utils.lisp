(in-package :hackmode)

(defun unix-now  ()
  (local-time:timestamp-to-unix (local-time:now)))
