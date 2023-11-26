(in-package :hackmode)



(conspack:defencoding meta
  doc-id tags dtype date-added date-updated operation)

(conspack:defencoding output
  doc-id tags dtype date-added date-updated operation tool output)


(conspack:defencoding host
  doc-id tags dtype date-added date-updated operation hostname ip)


(conspack:defencoding port
  doc-id tags dtype date-added date-updated operation number services)

(defvar *db* nil "The hackmode database object")


;; default to the one from tek9
;; This is effectivly just a wrapper around "put"
(defun put-doc (document &key (database-name "std") (database *db*))
  (when (not (doc-id document))
    (setf (doc-id document) (sxhash document)))
  (tek9:put* database document :id (doc-id document)))


(defun put-docs (documents &key (database-name "std") (database *db*))
  (tek9:put-bulk database (loop for doc in documents
                                collect (progn
                                          (let ((id (or (doc-id doc) (format nil "~a" (sxhash doc)))))
                                            (tek9:new-document :id id :value doc))))))
