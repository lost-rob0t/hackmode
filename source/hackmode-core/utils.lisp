(in-package :hackmode)

(defun flatten (lst)
  (let ((result '()))
    (labels ((rflatten (lst1)
               (dolist (el lst1)
                 (if (listp el)
                     (rflatten el)
                     (push el result)))))
      (rflatten lst)
      (nreverse result))))


(defun unix-now  ()
  (local-time:timestamp-to-unix (local-time:now)))


(defun make-command (command &rest args)
  (let* ((stream (make-string-output-stream))
         (*standard-output* stream)
         (code (shellpool:run (format nil "~a ~{~a~^ ~}" command args))))
    (list (get-output-stream-string stream) code)))
