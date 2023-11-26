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
