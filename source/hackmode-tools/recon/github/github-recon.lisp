(defpackage   :github-recon
  (:use :cl)
  (:documentation "Preform Recon on github users")
  (:export
   #:list-org-repos
   #:list-user-repos
   #:archive-repos))



(in-package :github-recon)

(defvar *client* (make-instance 'github-client:api-client) "The Github Cient")


(defun list-org-repos (org &key (limit 100))
  (let ((api-doc (make-instance 'github-api-doc:api-doc
                                :api "GET /orgs/:org/repos"
                                :parameters '(("type" "string"
                                               ("sort" "string")
                                               ("direction" "string")
                                               ("per_page" "integer")
                                               ("page" "integer"))))))
    (remove-duplicates  (mapcan #'identity (loop for i from 1 to (floor limit 100) collect (loop for obj in  (jsown:parse (github-client:github-api-call *client* api-doc :org  org :per_page 100 :page i))
                                                                                                 collect (jsown:val obj "html_url")))))))

(defun list-user-repos (username)
  (let ((api-doc (make-instance 'github-api-doc:api-doc
                                :api "GET /users/:username/repos"
                                :parameters '(("type" "string"
                                               ("sort" "string")
                                               ("direction" "string"))))))
    (loop for obj in  (jsown:parse (github-client:github-api-call *client* api-doc :username  username))
          collect (jsown:val obj "html_url"))))


(defun archive-repos (repos &key (path "./files/"))
  (loop for repo in repos
        for name = (nth 4 (uiop:split-string repo :separator "/"))


        for dl-path = (format nil "~a~a" path name)
        do (uiop:run-program (format t "git clone ~a ~a" repo dl-path))))
