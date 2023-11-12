(defpackage   :github-recon
  (:use :cl)
  (:documentation "Preform Recon on github users"))



(in-package :github-recon)

(defvar *client* (make-instance 'github-client:api-client) "The Github Cient")


(defun list-org-repos (org)
  (let ((api-doc (make-instance 'github-api-doc:api-doc
                                :api "GET /orgs/:org/repos"
                                :parameters '(("type" "string"
                                               ("sort" "string")
                                               ("direction" "string"))))))
    (loop for obj in  (jsown:parse (github-client:github-api-call *client* api-doc :org  org))
          collect (jsown:val obj "html_url"))))

(defun list-user-repos (username)
  (let ((api-doc (make-instance 'github-api-doc:api-doc
                                :api "GET /users/:username/repos"
                                :parameters '(("type" "string"
                                               ("sort" "string")
                                               ("direction" "string"))))))
    (loop for obj in  (jsown:parse (github-client:github-api-call *client* api-doc :username  username))
          collect (jsown:val obj "html_url"))))
