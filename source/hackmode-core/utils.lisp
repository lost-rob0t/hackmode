(in-package :hackmode)

(defun* (unix-now -> integer) ()
  (local-time:timestamp-to-unix (local-time:now)))
