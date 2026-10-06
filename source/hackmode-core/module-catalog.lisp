(in-package :hackmode-modules)

(defclass module-catalog-request ()
  ((data :initarg :data :reader %request-data)))

(defclass module-catalog-result ()
  ((data :initarg :data :reader %result-data)))

(defun %catalog-command (command)
  (let ((name (%name command :command)))
    (or (find name '(:families :list :describe :instantiate)
              :key (lambda (item) (string-downcase (symbol-name item)))
              :test #'string=)
        (%invalid :command "Unknown catalog command."))))

(defun make-module-catalog-request (&key request-id operation-id command id version
                                     family query tags capability options)
  "Make a copied local request. Instantiation requires an operation and exact version."
  (let* ((command (%catalog-command command))
         (needs-module (member command '(:describe :instantiate)))
         (info (list :request-id (%text request-id :request-id)
                     :operation-id (if (eq command :instantiate)
                                       (%text operation-id :operation-id)
                                       (%optional-text operation-id :operation-id))
                     :command command
                     :id (if needs-module (%name id :id) (when id (%name id :id)))
                     :version (if needs-module (%text version :version)
                                  (%optional-text version :version))
                     :family (when family (%name family :family))
                     :query (when query (%text query :query t))
                     :tags (%metadata-strings tags :tags)
                     :capability (when capability (%name capability :capability))
                     :options (%option-overrides options))))
    (make-instance 'module-catalog-request :data info)))

(defun %validated-request-data (request)
  ;; CLOS permits MAKE-INSTANCE even when the public constructor is bypassed.
  ;; Revalidate at the receiver boundary before any registry access.
  (unless (and (typep request 'module-catalog-request)
               (slot-boundp request 'data))
    (%invalid :request "Expected an initialized module catalog request."))
  (let ((info (%proper-list (%request-data request) :request))
        (keys nil))
    (unless (evenp (length info)) (%invalid :request "Expected a request property list."))
    (loop for tail on info by #'cddr
          for key = (car tail)
          do (unless (member key '(:request-id :operation-id :command :id :version
                                   :family :query :tags :capability :options))
               (%invalid :request "Unknown request field."))
             (when (member key keys) (%invalid :request "Duplicate request field."))
             (push key keys))
    (%request-data (apply #'make-module-catalog-request info))))

(defun %catalog-result (request-id operation-id status value)
  (make-instance 'module-catalog-result
                 :data (%copy-data (list :request-id request-id :operation-id operation-id
                                         :status status :value value)
                                   :result)))

(defun module-catalog-result-info (result)
  (unless (typep result 'module-catalog-result)
    (%invalid :result "Expected a module catalog result."))
  (%copy-data (%result-data result) :result))

(defun handle-module-catalog-request (request &key (registry *module-registry*))
  "Handle a typed request synchronously. Results never imply module execution."
  (let ((request-id nil) (operation-id nil))
    (handler-case
        (progn
          (let* ((info (%validated-request-data request))
                 (command (getf info :command)))
            (setf request-id (getf info :request-id)
                  operation-id (getf info :operation-id))
            (%registry registry)
            (case command
              (:families
               (%catalog-result request-id operation-id :ok
                                (list-module-families :registry registry)))
              (:list
               (%catalog-result
                request-id operation-id :ok
                (mapcar #'module-info
                        (list-modules :registry registry :family (getf info :family)
                                      :query (getf info :query) :tags (getf info :tags)
                                      :capability (getf info :capability)))))
              ((:describe :instantiate)
               (let ((descriptor (find-module (getf info :id) (getf info :version)
                                              :registry registry)))
                 (if descriptor
                     (%catalog-result
                      request-id operation-id :ok
                      (if (eq command :describe)
                          (module-info descriptor)
                          (module-instance-info
                           (instantiate-module descriptor operation-id
                                               :options (getf info :options)))))
                     (%catalog-result request-id operation-id :not-found nil))))
              (otherwise (%invalid :command "Unknown catalog command.")))))
      (module-validation-error (condition)
        (%catalog-result request-id operation-id :invalid-request
                         (list :field (module-error-field condition)
                               :reason (module-error-reason condition)))))))

(defun make-module-catalog-receiver (&key (registry *module-registry*) reply)
  "Return an in-process receiver; an optional callback receives a detached result.
The callback and return value never share mutable result data. Registry mutation
must be serialized by callers, or by the native catalog actor."
  (%registry registry)
  (unless (or (null reply) (functionp reply))
    (%invalid :reply "Expected a function or NIL."))
  (lambda (request)
    (let ((result (handle-module-catalog-request request :registry registry)))
      (when reply
        (funcall reply (make-instance 'module-catalog-result
                                     :data (module-catalog-result-info result))))
      result)))
