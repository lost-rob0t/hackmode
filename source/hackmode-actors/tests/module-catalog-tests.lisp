(in-package :hackmode-actors-tests)

(defun run-module-message-validation-test ()
  ;; Present empty values are distinct from missing fields in existing schemas.
  (assert (hackmode-actors:validate-ontology-message
           "hackmode/provider-result@1"
           '(("jobId" . "job") ("status" . "succeeded") ("assets"))))
  (assert (hackmode-actors:validate-ontology-message
           "hackmode/run-capability@1" '(("capability" . "fixture") ("input"))))
  (dolist (payload '((("jobId" . "job") ("status" . "succeeded") ("assets" 123))
                     (("jobId" . "job") ("status" . "succeeded"))))
    (assert (signals-condition-p
             'hackmode-actors:ontology-message-error
             (lambda () (hackmode-actors:validate-ontology-message
                         "hackmode/provider-result@1" payload)))))
  (assert (signals-condition-p
           'hackmode-actors:ontology-message-error
           (lambda () (hackmode-actors:validate-ontology-message
                       "host" '(("id" . "x") ("dataset" . "d") ("dtype" . "host")
                                ("schemaVersion" . "1") ("ip" . "192.0.2.1"))))))
  (assert (hackmode-actors::%wire-type-matches-p "boolean" nil))
  (assert (hackmode-actors::%wire-type-matches-p "boolean" t))
  (assert (not (hackmode-actors::%wire-type-matches-p "boolean" :null)))
  (assert (hackmode-actors::%wire-type-matches-p '(:optional "string") nil))
  (assert (not (hackmode-actors::%wire-type-matches-p "string" nil)))
  (let ((cycle (list "value")) (*print-circle* nil) (*print-length* 6))
    (setf (cdr cycle) cycle)
    (let ((message
            (handler-case
                (progn
                  (hackmode-actors:validate-ontology-message
                   "hackmode/provider-result@1"
                   (list '("jobId" . "job") '("status" . "succeeded") (cons "assets" cycle)))
                  nil)
              (hackmode-actors:ontology-message-error (condition)
                (hackmode-actors::ontology-error-message condition)))))
      (assert (and message (search "#1=" message))))))

(defun catalog-value (fields name) (cdr (assoc name fields :test #'string=)))

(defun catalog-request (type &rest fields)
  (hackmode-actors:make-ontology-wire-message
   type (append '(("requestId" . "catalog-request") ("operationId" . "op-catalog")) fields)))

(defun catalog-reply-payload (reply)
  (assert-equal "hackmode/module-catalog-result@1" (hackmode-actors:ontology-wire-message-type reply))
  (let ((payload (hackmode-actors:ontology-wire-message-payload reply)))
    (assert (hackmode-actors:validate-ontology-message "hackmode/module-catalog-result@1" payload))
    (assert-equal "catalog-request" (catalog-value payload "requestId"))
    (assert-equal "op-catalog" (catalog-value payload "operationId"))
    payload))

(defun module-test-registry ()
  (let ((registry (hackmode-modules:make-module-registry)))
    (dolist (family '(:recon :scan :fingerprinting :exploit :post-exploit :payload :custom-fixture))
      (hackmode-modules:register-module
       (hackmode-modules:make-module-descriptor
        :id (format nil "fixture/~(~a~)" family) :version "1" :family family
        :title "Catalog λ fixture" :tags '("fixture")
        :capability "fixture/observe" :provider "fixture"
        :options (list (hackmode-modules:make-module-option :name "flag" :type :boolean :default nil)
                       (hackmode-modules:make-module-option :name "mode" :type :enum
                                                           :choices '(:one "one" nil) :default :one))
        :result-schema '(:opaque ("value" . :lisp-value)))
       :registry registry))
    registry))

(defun run-module-manifest-test ()
  (multiple-value-bind (library actors manifest) (hackmode-actors:load-hackmode-ontology :force t)
    (declare (ignore library))
    (assert (= 7 (length actors)))
    (assert-equal '("hackmode/module-families-request@1" "hackmode/module-list-request@1"
                    "hackmode/module-describe-request@1")
                  (hackmode-actors:ontology-actor-accepts "module-catalog"))
    (assert-equal '("hackmode/module-catalog-result@1")
                  (hackmode-actors:ontology-actor-produces "module-catalog"))
    (let ((actor (find "module-catalog" (getf manifest :actors)
                       :key (lambda (actor) (getf actor :name)) :test #'string=)))
      (assert actor)
      (assert-equal "star://hackmode:localhost:module-catalog" (getf actor :service-uri)))
    (let* ((result (hackmode-actors:ontology-message-declaration "hackmode/module-catalog-result@1"))
           (modules (find "modules" (getf result :fields)
                          :key (lambda (field) (getf field :name)) :test #'string=)))
      (assert-equal '(:list "dev.hackmode/core@1/module-summary") (getf modules :type)))
    (assert (find "dev.hackmode/core@1/module-summary" (getf manifest :types)
                   :key (lambda (type) (getf type :name)) :test #'string=))))

(defun run-module-summary-test ()
  (let* ((registry (module-test-registry))
         (before (hackmode-modules:module-info
                  (hackmode-modules:find-module "fixture/exploit" "1" :registry registry))))
    (flet ((query (type &rest fields)
             (catalog-reply-payload
              (hackmode-actors:handle-module-catalog-message
               (apply #'catalog-request type fields) :registry registry))))
      (let ((reply (query "hackmode/module-families-request@1")))
        (assert-equal "ok" (catalog-value reply "status"))
        (assert-equal '("custom-fixture" "exploit" "fingerprinting" "payload" "post-exploit" "recon" "scan")
                      (catalog-value reply "families"))
        (assert (assoc "omittedFields" reply :test #'string=))
        (assert (null (catalog-value reply "omittedFields"))))
      (assert-equal "ok" (catalog-value (query "hackmode/module-families-request@1"
                                              '("detail" . "full") '("family" . 42)) "status"))
      (let* ((reply (query "hackmode/module-list-request@1" '("family" . "exploit")))
             (summaries (catalog-value reply "modules")) (summary (first summaries)))
        (assert (= 1 (length summaries)))
        (assert-equal "summary" (catalog-value reply "projection"))
        (assert-equal '("options" "resultSchema") (catalog-value reply "omittedFields"))
        (assert-equal "fixture/exploit" (catalog-value summary "id"))
        (assert-equal "Catalog λ fixture" (catalog-value summary "title"))
        (assert-equal "fixture/observe" (catalog-value summary "capability"))
        (assert-equal "fixture" (catalog-value summary "provider"))
        (assert (not (assoc "options" summary :test #'string=)))
        (assert (not (assoc "resultSchema" summary :test #'string=)))
        (setf (char (catalog-value summary "title") 0) #\X
              (char (catalog-value summary "lifecycle") 0) #\X
              (char (catalog-value reply "status") 0) #\X
              (char (first (catalog-value reply "omittedFields")) 0) #\X))
      (let ((reply (query "hackmode/module-list-request@1" '("family" . "absent"))))
        (assert-equal "ok" (catalog-value reply "status"))
        (assert (assoc "modules" reply :test #'string=))
        (assert (null (catalog-value reply "modules"))))
      (let* ((reply (query "hackmode/module-describe-request@1"
                           '("moduleId" . "fixture/exploit") '("moduleVersion" . "1")))
             (summary (catalog-value reply "module")))
        (assert-equal "Catalog λ fixture" (catalog-value summary "title"))
        (assert-equal "current" (catalog-value summary "lifecycle"))
        (assert-equal '("options" "resultSchema") (catalog-value reply "omittedFields")))
      (dolist (type '("hackmode/module-list-request@1" "hackmode/module-describe-request@1"))
        (let ((reply (query type '("moduleId" . "fixture/exploit") '("moduleVersion" . "1")
                                 '("detail" . "full"))))
          (assert-equal "unsupported" (catalog-value reply "status"))
          (assert-equal "none" (catalog-value reply "projection"))
          (assert-equal '("options" "resultSchema") (catalog-value reply "omittedFields"))
          (assert (not (assoc "modules" reply :test #'string=)))
          (assert (not (assoc "module" reply :test #'string=)))))
      (assert-equal "not-found" (catalog-value (query "hackmode/module-describe-request@1"
                                                      '("moduleId" . "fixture/exploit")
                                                      '("moduleVersion" . "2")) "status"))
      (assert-equal "invalid-request" (catalog-value (query "hackmode/module-describe-request@1"
                                                            '("moduleId" . "invalid id")
                                                            '("moduleVersion" . "1")) "status"))
      (assert-equal 7 (length (catalog-value (query "hackmode/module-list-request@1"
                                                   '("tags") '("query" . "fixture") '("moduleId" . 42)) "modules")))
      (dolist (bad-field '(("tags" 1) ("family")))
        (assert (signals-condition-p
                 'hackmode-actors:ontology-message-error
                 (lambda () (query "hackmode/module-list-request@1" bad-field)))))
      (assert (signals-condition-p
               'hackmode-actors:ontology-message-error
               (lambda () (query "hackmode/run-capability@1" '("capability" . "fixture") '("input"))))))
    (assert-equal before (hackmode-modules:module-info
                         (hackmode-modules:find-module "fixture/exploit" "1" :registry registry)))
    (dolist (request (list
                     (append (catalog-request "hackmode/module-list-request@1")
                             '(("type" . "hackmode/run-capability@1")))
                     (catalog-request "hackmode/module-list-request@1" '("family" . "scan") '("family" . "recon"))))
      (assert (signals-condition-p
               'hackmode-actors:ontology-message-error
               (lambda () (hackmode-actors:handle-module-catalog-message request :registry registry)))))
    (let* ((request (catalog-request "hackmode/module-list-request@1" '("extension" . "preserved")))
           (copy (copy-tree request)))
      (hackmode-actors:handle-module-catalog-message request :registry registry)
      (assert-equal copy request))
    (let* ((reply (hackmode-actors:handle-module-catalog-message
                   (hackmode-actors:make-ontology-wire-message
                    "hackmode/module-families-request@1" '(("requestId" . "unscoped"))) :registry registry))
           (payload (hackmode-actors:ontology-wire-message-payload reply)))
      (assert-equal "unscoped" (catalog-value payload "requestId"))
      (assert (not (assoc "operationId" payload :test #'string=))))
    (assert (signals-condition-p
             'hackmode-actors:ontology-message-error
             (lambda ()
               (hackmode-actors:validate-ontology-message
                "hackmode/module-catalog-result@1"
                '(("requestId" . "r") ("command" . "list") ("status" . "ok")
                  ("projection" . "summary") ("omittedFields" "options" "resultSchema")
                  ("modules" (("id" . "missing-other-required-fields"))))))))))

(defun run-module-ontology-actor-test ()
  (let ((old-registry hackmode-modules:*module-registry*) (old-system hackmode:*hackmode-actor-system*)
        (old-actors hackmode-actors:*ontology-actors*) (old-port hackmode-actors::*ontology-actor-port*)
        (system (sento.actor-system:make-actor-system
                 '(:dispatchers (:shared (:workers 1 :strategy :random)
                                  :providers (:workers 1 :strategy :random)
                                  :outbox (:workers 1 :strategy :random))))))
    (unwind-protect
         (progn
           (setf hackmode-modules:*module-registry* (module-test-registry)
                 hackmode:*hackmode-actor-system* system
                 hackmode-actors:*ontology-actors* nil hackmode-actors::*ontology-actor-port* nil)
           (assert (= 7 (length (hackmode-actors:ensure-hackmode-ontology-actors))))
           (let* ((request (catalog-request "hackmode/module-list-request@1" '("family" . "post-exploit")))
                  (reply (hackmode-actors:ask-hackmode-actor :module-catalog request :timeout 2)))
             (assert-equal (hackmode-actors:handle-module-catalog-message request) reply)
             (assert-equal "post-exploit"
                           (catalog-value (first (catalog-value (catalog-reply-payload reply) "modules")) "family")))
           (assert (signals-condition-p
                    'starsentocompat:sento-ask-failure-error
                    (lambda () (hackmode-actors:ask-hackmode-actor
                                :module-catalog (catalog-request "hackmode/run-capability@1"
                                                                '("capability" . "fixture") '("input")) :timeout 2))))
           (let ((reply (catalog-reply-payload
                         (hackmode-actors:ask-hackmode-actor
                          :module-catalog (catalog-request "hackmode/module-families-request@1") :timeout 2))))
             (assert (= 7 (length (catalog-value reply "families"))))))
      (hackmode-actors:stop-hackmode-ontology-actors)
      (sento.actor-context:shutdown system)
      (setf hackmode-modules:*module-registry* old-registry hackmode:*hackmode-actor-system* old-system
            hackmode-actors:*ontology-actors* old-actors hackmode-actors::*ontology-actor-port* old-port))))

(defun run-module-catalog-tests ()
  (run-module-message-validation-test)
  (run-module-manifest-test)
  (run-module-summary-test)
  (run-module-ontology-actor-test)
  (format t "Module ontology contracts, summary projection and actor tests passed.~%"))
