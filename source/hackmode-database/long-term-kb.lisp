(in-package :hackmode-database)

(define-condition long-term-kb-validation-error (error)
  ((field :initarg :field :reader long-term-kb-error-field)
   (value :initarg :value :reader long-term-kb-error-value)
   (reason :initarg :reason :reader long-term-kb-error-reason))
  (:report (lambda (condition stream)
             (format stream "Invalid long-term KB field ~S: ~A (~S)"
                     (long-term-kb-error-field condition)
                     (long-term-kb-error-reason condition)
                     (long-term-kb-error-value condition)))))

(defstruct (long-term-kb-promotion
             (:constructor %make-long-term-kb-promotion))
  record-id
  source-operation-id
  source-assertion-id
  source-run-id
  source-expert-id
  source-expert-version
  source-evidence-ids
  key
  value
  promoted-by
  promoter-version
  evidence-ids
  provenance)

(defun %long-term-require-string (field value)
  (unless (%non-empty-string-p value)
    (error 'long-term-kb-validation-error
           :field field :value value :reason "expected non-empty string"))
  value)

(defun %long-term-require-evidence (field value)
  (unless (and (listp value) value (every #'%non-empty-string-p value))
    (error 'long-term-kb-validation-error
           :field field :value value
           :reason "at least one non-empty evidence ID is required"))
  value)

(defun long-term-kb-graph-name ()
  "Return the canonical reusable-knowledge graph name."
  "hackmode/kb/long-term")

(defun long-term-kb-root-id ()
  (%record-id "long-term-kb-root"))

(defun make-long-term-kb-promotion
    (&key promotion-id source-assertion promoted-by promoter-version
          evidence-ids provenance)
  "Create one immutable evidence-backed promotion from operational knowledge.

Promotion copies the source assertion's semantic value and provenance identity.
It never mutates or deletes the operational assertion and does not imply global
export. Multiple operations may independently promote corroborating knowledge."
  (%long-term-require-string :promotion-id promotion-id)
  (%long-term-require-string :promoted-by promoted-by)
  (%long-term-require-string :promoter-version promoter-version)
  (%long-term-require-evidence :evidence-ids evidence-ids)
  (unless provenance
    (error 'long-term-kb-validation-error
           :field :provenance :value provenance :reason "provenance is required"))
  (unless (typep source-assertion 'operational-kb-entry)
    (error 'long-term-kb-validation-error
           :field :source-assertion :value source-assertion
           :reason "expected operational KB entry"))
  (unless (eq :assert (operational-kb-entry-kind source-assertion))
    (error 'long-term-kb-validation-error
           :field :source-assertion :value source-assertion
           :reason "only operational assertions may be promoted"))
  (%long-term-require-evidence
   :source-evidence-ids
   (operational-kb-entry-evidence-ids source-assertion))
  (%make-long-term-kb-promotion
   :record-id (%record-id "long-term-kb-promotion"
                          (operational-kb-entry-operation-id source-assertion)
                          (operational-kb-entry-record-id source-assertion)
                          promotion-id)
   :source-operation-id (operational-kb-entry-operation-id source-assertion)
   :source-assertion-id (operational-kb-entry-record-id source-assertion)
   :source-run-id (operational-kb-entry-run-id source-assertion)
   :source-expert-id (operational-kb-entry-expert-id source-assertion)
   :source-expert-version (operational-kb-entry-expert-version source-assertion)
   :source-evidence-ids (copy-list
                         (operational-kb-entry-evidence-ids source-assertion))
   :key (operational-kb-entry-key source-assertion)
   :value (operational-kb-entry-value source-assertion)
   :promoted-by promoted-by
   :promoter-version promoter-version
   :evidence-ids (copy-list evidence-ids)
   :provenance provenance))

(defun long-term-kb-promotion->tek9-node (promotion)
  (make-instance 'tek9:node
                 :id (long-term-kb-promotion-record-id promotion)
                 :props
                 (list :kind :long-term-kb-promotion
                       :source-operation-id
                       (long-term-kb-promotion-source-operation-id promotion)
                       :source-assertion-id
                       (long-term-kb-promotion-source-assertion-id promotion)
                       :source-run-id
                       (long-term-kb-promotion-source-run-id promotion)
                       :source-expert-id
                       (long-term-kb-promotion-source-expert-id promotion)
                       :source-expert-version
                       (long-term-kb-promotion-source-expert-version promotion)
                       :source-evidence-ids
                       (long-term-kb-promotion-source-evidence-ids promotion)
                       :key (long-term-kb-promotion-key promotion)
                       :value (long-term-kb-promotion-value promotion)
                       :promoted-by (long-term-kb-promotion-promoted-by promotion)
                       :promoter-version
                       (long-term-kb-promotion-promoter-version promotion)
                       :evidence-ids
                       (long-term-kb-promotion-evidence-ids promotion)
                       :provenance
                       (long-term-kb-promotion-provenance promotion))))

(defun tek9-node->long-term-kb-promotion (node)
  "Reconstruct and validate one typed long-term promotion from NODE."
  (let ((props (tek9:node-props node)))
    (unless (eq :long-term-kb-promotion (getf props :kind))
      (error 'long-term-kb-validation-error
             :field :kind :value (getf props :kind)
             :reason "expected long-term KB promotion node"))
    (let ((record-id (%long-term-require-string :record-id (tek9:node-id node)))
          (source-operation-id
            (%long-term-require-string
             :source-operation-id (getf props :source-operation-id)))
          (source-assertion-id
            (%long-term-require-string
             :source-assertion-id (getf props :source-assertion-id)))
          (source-run-id
            (%long-term-require-string :source-run-id (getf props :source-run-id)))
          (source-expert-id
            (%long-term-require-string
             :source-expert-id (getf props :source-expert-id)))
          (source-expert-version
            (%long-term-require-string
             :source-expert-version (getf props :source-expert-version)))
          (source-evidence-ids
            (%long-term-require-evidence
             :source-evidence-ids (getf props :source-evidence-ids)))
          (promoted-by
            (%long-term-require-string :promoted-by (getf props :promoted-by)))
          (promoter-version
            (%long-term-require-string
             :promoter-version (getf props :promoter-version)))
          (evidence-ids
            (%long-term-require-evidence :evidence-ids (getf props :evidence-ids)))
          (provenance (getf props :provenance)))
      (unless provenance
        (error 'long-term-kb-validation-error
               :field :provenance :value provenance :reason "provenance is required"))
      (%make-long-term-kb-promotion
       :record-id record-id
       :source-operation-id source-operation-id
       :source-assertion-id source-assertion-id
       :source-run-id source-run-id
       :source-expert-id source-expert-id
       :source-expert-version source-expert-version
       :source-evidence-ids (copy-list source-evidence-ids)
       :key (getf props :key)
       :value (getf props :value)
       :promoted-by promoted-by
       :promoter-version promoter-version
       :evidence-ids (copy-list evidence-ids)
       :provenance provenance))))

(defun long-term-kb-root-node ()
  (make-instance 'tek9:node
                 :id (long-term-kb-root-id)
                 :props (list :kind :long-term-kb-root)))

(defun long-term-kb-source-reference-node (promotion)
  "Return an immutable graph-local foreign-key anchor for PROMOTION's source."
  (make-instance 'tek9:node
                 :id (long-term-kb-promotion-source-assertion-id promotion)
                 :props
                 (list :kind :operational-kb-reference
                       :source-operation-id
                       (long-term-kb-promotion-source-operation-id promotion)
                       :source-run-id
                       (long-term-kb-promotion-source-run-id promotion)
                       :source-expert-id
                       (long-term-kb-promotion-source-expert-id promotion)
                       :source-expert-version
                       (long-term-kb-promotion-source-expert-version promotion))))

(defun long-term-kb-membership-edge (promotion)
  (make-instance 'tek9:edge
                 :id (%record-id "long-term-kb-membership"
                                 (long-term-kb-promotion-record-id promotion))
                 :source (long-term-kb-root-id)
                 :predicate :contains
                 :target (long-term-kb-promotion-record-id promotion)))

(defun long-term-kb-source-edge (promotion)
  "Return the provenance edge back to the exact operational assertion ID."
  (make-instance 'tek9:edge
                 :id (%record-id "long-term-kb-promoted-from"
                                 (long-term-kb-promotion-record-id promotion)
                                 (long-term-kb-promotion-source-assertion-id promotion))
                 :source (long-term-kb-promotion-record-id promotion)
                 :predicate :promoted-from
                 :target (long-term-kb-promotion-source-assertion-id promotion)))
