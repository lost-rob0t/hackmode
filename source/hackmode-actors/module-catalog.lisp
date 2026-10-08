(in-package :hackmode-actors)

(defun copy-catalog-wire-data (value)
  "Detach projected data without changing its shape or encoding Lisp values."
  (typecase value
    (string (copy-seq value))
    (cons (cons (copy-catalog-wire-data (car value)) (copy-catalog-wire-data (cdr value))))
    (integer value)
    (null nil)
    (t (if (eq value t) t
           (error 'ontology-message-error :message "non-portable catalog projection value")))))

(defun module-summary-fields (info)
  "Project known fields; original options and result-schema stay in the catalog."
  (let ((fields
          (loop for (wire-key . local-key) in
                '(("schemaVersion" . :schema-version)
                  ("id" . :id) ("version" . :version) ("family" . :family)
                  ("title" . :title) ("description" . :description)
                  ("authors" . :authors) ("tags" . :tags) ("references" . :references)
                  ("platforms" . :platforms) ("architectures" . :architectures)
                  ("sessionTypes" . :session-types) ("compatiblePayloads" . :compatible-payloads))
                collect (cons (copy-seq wire-key) (getf info local-key)))))
    (dolist (binding '(("capability" . :capability) ("provider" . :provider)))
      (when (getf info (cdr binding))
        (push (cons (copy-seq (car binding)) (getf info (cdr binding))) fields)))
    (append fields (list (cons "lifecycle"
                               (ecase (getf info :lifecycle)
                                 (:current "current") (:deprecated "deprecated")))))))

(defun module-catalog-command (message-type)
  (cond
    ((string= message-type "hackmode/module-families-request@1") :families)
    ((string= message-type "hackmode/module-list-request@1") :list)
    ((string= message-type "hackmode/module-describe-request@1") :describe)
    (t (error 'ontology-message-error :message "unsupported module catalog request"))))

(defun module-catalog-reply (request command status projection fields &key omitted-fields)
  (let ((payload
          (append
           (list (cons "requestId" (copy-seq (%payload-value request "requestId")))
                 (cons "command" (string-downcase (symbol-name command)))
                 (cons "status" status) (cons "projection" projection)
                 (cons "omittedFields" (mapcar #'copy-seq omitted-fields)))
           (when (assoc "operationId" request :test #'string=)
             (list (cons "operationId" (copy-seq (%payload-value request "operationId")))))
           fields)))
    (validate-ontology-message "hackmode/module-catalog-result@1" payload)
    (unless (member "hackmode/module-catalog-result@1"
                    (ontology-actor-produces "module-catalog") :test #'string=)
      (error 'ontology-message-error :message "catalog result is not declared by actor"))
    (copy-catalog-wire-data
     (make-ontology-wire-message "hackmode/module-catalog-result@1" payload))))

(defun handle-module-catalog-message (message &key (registry hackmode-modules:*module-registry*))
  "Answer declared summary queries through the existing local catalog API.
Full metadata is unsupported until a lossless wire value carrier is agreed."
  (unless (%wire-map-p message)
    (error 'ontology-message-error :message "module catalog envelope must be an alist"))
  (unless (= (length message) (length (remove-duplicates message :key #'car :test #'string=)))
    (error 'ontology-message-error :message "duplicate module catalog envelope field"))
  (let* ((message-type (ontology-wire-message-type message))
         (payload (ontology-wire-message-payload message)))
    (unless (member message-type (ontology-actor-accepts "module-catalog") :test #'equal)
      (error 'ontology-message-error :message "message is not accepted by module-catalog"))
    (validate-ontology-message message-type payload)
    (unless (= (length payload) (length (remove-duplicates payload :key #'car :test #'string=)))
      (error 'ontology-message-error :message "duplicate module catalog request field"))
    (let ((command (module-catalog-command message-type)))
      (handler-case
          (let ((request
                  (apply #'hackmode-modules:make-module-catalog-request
                         :request-id (%payload-value payload "requestId")
                         :operation-id (%payload-value payload "operationId")
                         :command command
                         (ecase command
                           (:families nil)
                           (:list (list :family (%payload-value payload "family")
                                        :query (%payload-value payload "query")
                                        :tags (%payload-value payload "tags")
                                        :capability (%payload-value payload "capability")))
                           (:describe (list :id (%payload-value payload "moduleId")
                                            :version (%payload-value payload "moduleVersion")))))))
            (if (and (member command '(:list :describe)) (equal "full" (%payload-value payload "detail")))
                (module-catalog-reply
                 payload command "unsupported" "none"
                 '(("errorField" . "detail")
                   ("errorReason" . "Full Lisp metadata has no agreed wire value carrier; use the local catalog API."))
                 :omitted-fields '("options" "resultSchema"))
                (let* ((result (hackmode-modules:module-catalog-result-info
                                (hackmode-modules:handle-module-catalog-request request :registry registry)))
                       (status (getf result :status)) (value (getf result :value)))
                  (ecase status
                    (:ok
                     (module-catalog-reply
                      payload command "ok" "summary"
                      (ecase command
                        (:families (list (cons "families" value)))
                        (:list (list (cons "modules" (mapcar #'module-summary-fields value))))
                        (:describe (list (cons "module" (module-summary-fields value)))))
                      :omitted-fields (unless (eq command :families) '("options" "resultSchema"))))
                    (:not-found
                     (module-catalog-reply payload command "not-found" "none"
                                           '(("errorField" . "moduleId")
                                             ("errorReason" . "No module is registered for that exact ID/version."))))
                    (:invalid-request
                     (module-catalog-reply
                      payload command "invalid-request" "none"
                      (list (cons "errorField" (string-downcase (string (getf value :field))))
                            (cons "errorReason" (getf value :reason)))))))))
        (hackmode-modules:module-validation-error (condition)
          (module-catalog-reply
           payload command "invalid-request" "none"
           (list (cons "errorField" (string-downcase (string (hackmode-modules:module-error-field condition))))
                 (cons "errorReason" (hackmode-modules:module-error-reason condition)))))))))
