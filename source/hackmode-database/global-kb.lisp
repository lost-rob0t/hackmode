(in-package :hackmode-database)

(define-condition global-kb-validation-error (error)
  ((field :initarg :field :reader global-kb-error-field)
   (value :initarg :value :reader global-kb-error-value)
   (reason :initarg :reason :reader global-kb-error-reason))
  (:report (lambda (condition stream)
             (format stream "Invalid global KB field ~S: ~A (~S)"
                     (global-kb-error-field condition)
                     (global-kb-error-reason condition)
                     (global-kb-error-value condition)))))

(defstruct (global-kb-export
             (:constructor %make-global-kb-export))
  record-id
  source-promotion-id
  source-operation-id
  source-assertion-id
  source-run-id
  source-expert-id
  source-expert-version
  source-evidence-ids
  promotion-evidence-ids
  key
  value
  exported-by
  exporter-version
  evidence-ids
  provenance)

(defun %global-require-string (field value)
  (unless (%non-empty-string-p value)
    (error 'global-kb-validation-error
           :field field :value value :reason "expected non-empty string"))
  value)

(defun %global-require-evidence (field value)
  (unless (and (listp value) value (every #'%non-empty-string-p value))
    (error 'global-kb-validation-error
           :field field :value value
           :reason "at least one non-empty evidence ID is required"))
  value)

(defun global-kb-graph-name ()
  "Return the canonical explicitly exported reusable-knowledge graph name."
  "hackmode/kb/global")

(defun global-kb-root-id ()
  (%record-id "global-kb-root"))

(defun make-global-kb-export
    (&key export-id source-promotion exported-by exporter-version
          evidence-ids provenance)
  "Create one explicit immutable export from long-term knowledge.

The exported key/value and source provenance are copied from SOURCE-PROMOTION.
Callers cannot rewrite the promoted claim while exporting it. Constructing an
export does not persist it; persistence remains an explicit canonical Tek9 write."
  (%global-require-string :export-id export-id)
  (%global-require-string :exported-by exported-by)
  (%global-require-string :exporter-version exporter-version)
  (%global-require-evidence :evidence-ids evidence-ids)
  (unless provenance
    (error 'global-kb-validation-error
           :field :provenance :value provenance :reason "provenance is required"))
  (unless (typep source-promotion 'long-term-kb-promotion)
    (error 'global-kb-validation-error
           :field :source-promotion :value source-promotion
           :reason "expected long-term KB promotion"))
  (%global-require-evidence
   :source-evidence-ids
   (long-term-kb-promotion-source-evidence-ids source-promotion))
  (%global-require-evidence
   :promotion-evidence-ids
   (long-term-kb-promotion-evidence-ids source-promotion))
  (%make-global-kb-export
   :record-id (%record-id "global-kb-export"
                          (long-term-kb-promotion-record-id source-promotion)
                          export-id)
   :source-promotion-id (long-term-kb-promotion-record-id source-promotion)
   :source-operation-id (long-term-kb-promotion-source-operation-id source-promotion)
   :source-assertion-id (long-term-kb-promotion-source-assertion-id source-promotion)
   :source-run-id (long-term-kb-promotion-source-run-id source-promotion)
   :source-expert-id (long-term-kb-promotion-source-expert-id source-promotion)
   :source-expert-version
   (long-term-kb-promotion-source-expert-version source-promotion)
   :source-evidence-ids
   (copy-list (long-term-kb-promotion-source-evidence-ids source-promotion))
   :promotion-evidence-ids
   (copy-list (long-term-kb-promotion-evidence-ids source-promotion))
   :key (long-term-kb-promotion-key source-promotion)
   :value (long-term-kb-promotion-value source-promotion)
   :exported-by exported-by
   :exporter-version exporter-version
   :evidence-ids (copy-list evidence-ids)
   :provenance provenance))

(defun global-kb-export->tek9-node (export)
  (make-instance 'tek9:node
                 :id (global-kb-export-record-id export)
                 :props
                 (list :kind :global-kb-export
                       :source-promotion-id
                       (global-kb-export-source-promotion-id export)
                       :source-operation-id
                       (global-kb-export-source-operation-id export)
                       :source-assertion-id
                       (global-kb-export-source-assertion-id export)
                       :source-run-id
                       (global-kb-export-source-run-id export)
                       :source-expert-id
                       (global-kb-export-source-expert-id export)
                       :source-expert-version
                       (global-kb-export-source-expert-version export)
                       :source-evidence-ids
                       (global-kb-export-source-evidence-ids export)
                       :promotion-evidence-ids
                       (global-kb-export-promotion-evidence-ids export)
                       :key (global-kb-export-key export)
                       :value (global-kb-export-value export)
                       :exported-by (global-kb-export-exported-by export)
                       :exporter-version
                       (global-kb-export-exporter-version export)
                       :evidence-ids
                       (global-kb-export-evidence-ids export)
                       :provenance
                       (global-kb-export-provenance export))))

(defun global-kb-root-node ()
  (make-instance 'tek9:node
                 :id (global-kb-root-id)
                 :props (list :kind :global-kb-root)))

(defun global-kb-membership-edge (export)
  (make-instance 'tek9:edge
                 :id (%record-id "global-kb-membership"
                                 (global-kb-export-record-id export))
                 :source (global-kb-root-id)
                 :predicate :contains
                 :target (global-kb-export-record-id export)))

(defun global-kb-source-edge (export)
  "Return the provenance edge to the exact long-term promotion record."
  (make-instance 'tek9:edge
                 :id (%record-id "global-kb-exported-from"
                                 (global-kb-export-record-id export)
                                 (global-kb-export-source-promotion-id export))
                 :source (global-kb-export-record-id export)
                 :predicate :exported-from
                 :target (global-kb-export-source-promotion-id export)))
