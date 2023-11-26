(in-package :hackmode)

;;;  This file is ment to handle the handling of operation, which put simply is just a current working directory
;;;  This is the common pattern when doing hacking i find myself in
(defvar *operations-database* (tek9:new-database "operations" :path hackmode-operations-database))

(nhooks:add-hook *startup-hook* #'(lambda ()
                                    (tek9:open-database *operations-database*)))



(defclass operation (meta)
  ((working-dir :initarg :dir :accessor operation-dir :initform (uiop/os:getcwd) :allocation :class)
   (name :initarg :name :accessor operation-name :initform "" :allocation :class)
   (description :initarg :description :accessor operation-description :initform "" :allocation :class)))

(defvar *current-operation* nil "The current operation")


(defun new-operation (name &optional (path (uiop:merge-pathnames* ".hackmode/" (uiop:getcwd)) ) (description "Hackmode operation"))
  (let ((doc (make-instance 'operation :name name :description description :dir path :dtype "operation")))
    (tek9:put* *operations-database* doc :id  (operation-name doc))))

;; TODO A function/helper should do this!





;; NOTE For others reading the source code of hackmode this is a good example
;; On how to query tek9
(defun select-operation (name)
  "Selection query for tek9."
  (tek9:fetch* *operations-database* name))


(defun use-operation (name)
  "Select a operation by name to be the current operation."
  (let* ((op (select-operation name))
         (dir (if op (operation-dir op) (error (format nil  "No Such Operation exist. Use (hackmode:new-operation \"~a\") to create one" name)))))
    (setq *current-operation* op)
    (uiop:ensure-all-directories-exist (list dir))
    (when *db*
      (tek9:close-database *db*))
    (setq *db* (tek9:new-database name :path (uiop:merge-pathnames* (uiop:parse-unix-namestring dir) (format nil ".hackmode/"))))
    (tek9:open-database *db*)
    (uiop:chdir dir)))
