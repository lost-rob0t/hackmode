(in-package :hackmode-database)

(defvar *db* nil "The hackmode database object")


(defun make-document (data &key (id (make-ke))))

;; default to the one from tek9
;; This is effectivly just a wrapper around "put"
(defun put-doc (database document &key (database-name "std"))
  (tek9:put* database document :key (sxhash)))


(defun put-docs (database documents &key (database-name "std"))
  (loop for))
