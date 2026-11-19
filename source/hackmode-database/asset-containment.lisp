(in-package :hackmode-database)

;;; Operation-scoped asset containment records.
;;;
;;; One typed node per child asset whose discovery carried a parent:
;;; the red-team attack-surface closure (expert plane) consumes this
;;; through FETCH-ASSET-CONTAINMENT and the expert snapshot. Stored as
;;; nodes (not edges) so no cross-node graph-locality constraint
;;; applies; identity is (operation, child, parent).

(define-condition asset-containment-validation-error (error)
  ((field :initarg :field :reader asset-containment-error-field)
   (value :initarg :value :reader asset-containment-error-value)
   (reason :initarg :reason :reader asset-containment-error-reason))
  (:report (lambda (condition stream)
             (format stream "Invalid asset containment field ~S: ~A (~S)"
                     (asset-containment-error-field condition)
                     (asset-containment-error-reason condition)
                     (asset-containment-error-value condition)))))

(defstruct (asset-containment-record (:constructor %make-asset-containment-record))
  operation-id
  child-id
  parent-id)

(defun asset-containment-graph-name (operation-id)
  (%require-string :operation-id operation-id)
  (format nil "hackmode/assets/~A" (%key-part operation-id)))

(defun %containment-require-string (field value)
  (unless (and (stringp value) (plusp (length value)))
    (error 'asset-containment-validation-error
           :field field :value value :reason "expected non-empty string"))
  value)

(defun make-asset-containment-record (&key operation-id child-id parent-id)
  "Build one typed child-under-parent containment record."
  (%containment-require-string :operation-id operation-id)
  (%containment-require-string :child-id child-id)
  (%containment-require-string :parent-id parent-id)
  (%make-asset-containment-record
   :operation-id operation-id :child-id child-id :parent-id parent-id))

(defun asset-containment-record-id (record)
  (format nil "asset-containment/~A/~A"
          (%key-part (asset-containment-record-child-id record))
          (%key-part (asset-containment-record-parent-id record))))

(defun asset-containment->tek9-node (record)
  (make-instance 'tek9:node
                 :id (asset-containment-record-id record)
                 :props (list :kind :asset-containment
                             :operation-id (asset-containment-record-operation-id record)
                             :child-id (asset-containment-record-child-id record)
                             :parent-id (asset-containment-record-parent-id record))))

(defun tek9-node->asset-containment (node)
  "Reconstruct one typed containment record from a canonical Tek9 graph node."
  (let* ((props (tek9:node-props node))
         (kind (getf props :kind))
         (operation-id (getf props :operation-id))
         (child-id (getf props :child-id))
         (parent-id (getf props :parent-id)))
    (unless (eq kind :asset-containment)
      (error 'asset-containment-validation-error
             :field :kind :value kind
             :reason "unsupported stored asset containment kind"))
    (make-asset-containment-record
     :operation-id (%containment-require-string :operation-id operation-id)
     :child-id (%containment-require-string :child-id child-id)
     :parent-id (%containment-require-string :parent-id parent-id))))

(defun persist-asset-containment (database record)
  "Persist one typed containment RECORD into its operation-scoped Tek9 graph."
  (tek9:with-write-transaction (database)
    (persist-graph-node-replay-safe
     database
     (asset-containment->tek9-node record)
     :database-name (asset-containment-graph-name
                     (asset-containment-record-operation-id record))))
  record)

(defun fetch-asset-containment (database operation-id)
  "Return typed containment rows for one operation in deterministic order."
  (%containment-require-string :operation-id operation-id)
  (let ((records
          (loop for node in (tek9:fetch-graph-nodes
                             database (asset-containment-graph-name operation-id))
                for record = (tek9-node->asset-containment node)
                unless (string= operation-id
                                (asset-containment-record-operation-id record))
                  do (error 'asset-containment-validation-error
                            :field :operation-id
                            :value (asset-containment-record-operation-id record)
                            :reason "stored containment does not match graph operation scope")
                collect record)))
    (sort records #'string< :key #'asset-containment-record-child-id)))
