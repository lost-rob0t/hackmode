(in-package :hackmode)



(defun main ()
  (load hackmode-init-file)
  (setq *history* (make-instance 'history))
  (load-history))
