(in-package :hackmode)

(conspack:defencoding meta
  doc-id tags dtype date-added date-updated operation tool)

(conspack:defencoding output
  doc-id tags dtype date-added date-updated operation tool output)

(conspack:defencoding domain
  doc-id tags dtype date-added date-updated operation tool
  ips record record-type zone)

(conspack:defencoding host
  doc-id tags dtype date-added date-updated operation tool hostname ip)

(conspack:defencoding port
  doc-id tags dtype date-added date-updated operation tool number services)

(conspack:defencoding finding
  doc-id tags dtype date-added date-updated operation tool
  id finding-document-id finding-type data)

(conspack:defencoding url
  doc-id tags dtype date-added date-updated operation tool
  scheme host port path query)

(conspack:defencoding cert
  doc-id tags dtype date-added date-updated operation tool
  not-before not-after common-name org-unit-name locality country-name province)

(defvar *db* nil "The active Hackmode operation database object.")

(defun put-doc (document &key (database-name "std") (database *db*))
  "Persist DOCUMENT in DATABASE under its document id."
  (unless database
    (error "No Hackmode operation database is open."))
  (unless (and (doc-id document) (stringp (doc-id document)))
    (setf (doc-id document) (tek9:make-key-id)))
  (tek9:put* database document
             :id (doc-id document)
             :database-name database-name))

(defun put-docs (documents &key (database-name "std") (database *db*))
  "Persist DOCUMENTS in one Tek9 bulk write."
  (unless database
    (error "No Hackmode operation database is open."))
  (tek9:put-bulk
   database
   (loop for doc in documents
         for id = (or (and (stringp (doc-id doc)) (doc-id doc))
                      (tek9:make-key-id))
         do (setf (doc-id doc) id)
         collect (tek9:new-document :id id :value doc))
   :database-name database-name))
