(in-package :hackmode-database)

(define-condition operational-kb-validation-error (error)
  ((field :initarg :field :reader operational-kb-error-field)
   (value :initarg :value :reader operational-kb-error-value)
   (reason :initarg :reason :reader operational-kb-error-reason))
  (:report (lambda (condition stream)
             (format stream "Invalid operational KB field ~S: ~A (~S)"
                     (operational-kb-error-field condition)
                     (operational-kb-error-reason condition)
                     (operational-kb-error-value condition)))))

(defstruct (operational-kb-entry (:constructor %make-operational-kb-entry))
  kind
  operation-id
  run-id
  expert-id
  expert-version
  record-id
  key
  value
  target-assertion-id
  evidence-ids
  provenance)

(defun %kb-require-string (field value)
  (unless (%non-empty-string-p value)
    (error 'operational-kb-validation-error
           :field field :value value :reason "expected non-empty string"))
  value)

(defun %kb-require-provenance (value)
  (unless value
    (error 'operational-kb-validation-error
           :field :provenance :value value :reason "provenance is required"))
  value)

(defun %kb-require-evidence (value)
  (unless (and (listp value) value (every #'%non-empty-string-p value))
    (error 'operational-kb-validation-error
           :field :evidence-ids :value value
           :reason "at least one non-empty evidence ID is required"))
  value)

(defun operational-kb-graph-name (operation-id)
  (%kb-require-string :operation-id operation-id)
  (format nil "hackmode/kb/operational/~A" (%key-part operation-id)))

(defun operational-kb-root-id (operation-id)
  (%record-id "operational-kb-root" operation-id))

(defun %operational-kb-assertion-prefix (operation-id)
  (%record-id "operational-kb-assertion" operation-id))

(defun make-operational-kb-assertion
    (&key assertion-id operation-id run-id expert-id expert-version
          key value evidence-ids provenance)
  (%kb-require-string :assertion-id assertion-id)
  (%kb-require-string :operation-id operation-id)
  (%kb-require-string :run-id run-id)
  (%kb-require-string :expert-id expert-id)
  (%kb-require-string :expert-version expert-version)
  (%kb-require-evidence evidence-ids)
  (%kb-require-provenance provenance)
  (when (null key)
    (error 'operational-kb-validation-error
           :field :key :value key :reason "assertion key is required"))
  (%make-operational-kb-entry
   :kind :assert
   :operation-id operation-id
   :run-id run-id
   :expert-id expert-id
   :expert-version expert-version
   :record-id (%record-id "operational-kb-assertion"
                          operation-id assertion-id)
   :key key
   :value value
   :evidence-ids (copy-list evidence-ids)
   :provenance provenance))

(defun make-operational-kb-retraction
    (&key retraction-id operation-id run-id expert-id expert-version
          target-assertion-id evidence-ids provenance)
  (%kb-require-string :retraction-id retraction-id)
  (%kb-require-string :operation-id operation-id)
  (%kb-require-string :run-id run-id)
  (%kb-require-string :expert-id expert-id)
  (%kb-require-string :expert-version expert-version)
  (%kb-require-string :target-assertion-id target-assertion-id)
  (%kb-require-evidence evidence-ids)
  (%kb-require-provenance provenance)
  (let ((prefix (%operational-kb-assertion-prefix operation-id)))
    (unless (and (<= (length prefix) (length target-assertion-id))
                 (string= prefix target-assertion-id :end2 (length prefix)))
      (error 'operational-kb-validation-error
             :field :target-assertion-id
             :value target-assertion-id
             :reason "target assertion is outside the operation scope")))
  (%make-operational-kb-entry
   :kind :retract
   :operation-id operation-id
   :run-id run-id
   :expert-id expert-id
   :expert-version expert-version
   :record-id (%record-id "operational-kb-retraction"
                          operation-id retraction-id)
   :target-assertion-id target-assertion-id
   :evidence-ids (copy-list evidence-ids)
   :provenance provenance))

(defun operational-kb-entry->tek9-node (entry)
  (make-instance 'tek9:node
                 :id (operational-kb-entry-record-id entry)
                 :props (list :kind (operational-kb-entry-kind entry)
                              :operation-id (operational-kb-entry-operation-id entry)
                              :run-id (operational-kb-entry-run-id entry)
                              :expert-id (operational-kb-entry-expert-id entry)
                              :expert-version (operational-kb-entry-expert-version entry)
                              :key (operational-kb-entry-key entry)
                              :value (operational-kb-entry-value entry)
                              :target-assertion-id
                              (operational-kb-entry-target-assertion-id entry)
                              :evidence-ids
                              (operational-kb-entry-evidence-ids entry)
                              :provenance
                              (operational-kb-entry-provenance entry))))

(defun operational-kb-root-node (operation-id)
  (make-instance 'tek9:node
                 :id (operational-kb-root-id operation-id)
                 :props (list :kind :operational-kb-root
                              :operation-id operation-id)))

(defun operational-kb-membership-edge (assertion)
  (unless (eq :assert (operational-kb-entry-kind assertion))
    (error 'operational-kb-validation-error
           :field :kind :value (operational-kb-entry-kind assertion)
           :reason "membership edge requires assertion"))
  (make-instance 'tek9:edge
                 :id (%record-id "operational-kb-membership"
                                 (operational-kb-entry-operation-id assertion)
                                 (operational-kb-entry-record-id assertion))
                 :source (operational-kb-root-id
                          (operational-kb-entry-operation-id assertion))
                 :predicate :contains
                 :target (operational-kb-entry-record-id assertion)))

(defun operational-kb-retraction-edge (retraction)
  (unless (eq :retract (operational-kb-entry-kind retraction))
    (error 'operational-kb-validation-error
           :field :kind :value (operational-kb-entry-kind retraction)
           :reason "retraction edge requires retraction"))
  (make-instance 'tek9:edge
                 :id (%record-id "operational-kb-retracted-by"
                                 (operational-kb-entry-operation-id retraction)
                                 (operational-kb-entry-target-assertion-id retraction)
                                 (operational-kb-entry-record-id retraction))
                 :source (operational-kb-entry-target-assertion-id retraction)
                 :predicate :retracted-by
                 :target (operational-kb-entry-record-id retraction)))
