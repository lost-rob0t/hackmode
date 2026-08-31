(in-package :hackmode-database)

(defstruct (visual-evidence-record (:constructor %make-visual-evidence-record))
  operation-id
  run-id
  job-id
  record-id
  asset-id
  requested-url
  final-url
  screenshot-evidence-ref
  screenshot-digest
  captured-at
  title
  http-status
  viewport
  client-profile-id
  browser-id
  browser-version
  duration-ms
  body-digest
  technology-hints
  capture-session-id
  exchange-id
  failure-classification
  provenance)

(defun %validate-visual-evidence-http-status (value)
  (when value
    (%require-http-status value))
  value)

(defun %validate-visual-evidence-hints (value)
  (when value
    (unless (and (listp value)
                 (every #'%non-empty-string-p value))
      (error 'execution-graph-validation-error
             :field :technology-hints
             :value value
             :reason "expected a list of non-empty strings")))
  value)

(defun make-visual-evidence-record
    (&key operation-id run-id job-id asset-id requested-url final-url
          screenshot-evidence-ref screenshot-digest captured-at title http-status
          viewport client-profile-id browser-id browser-version duration-ms
          body-digest technology-hints capture-session-id exchange-id
          failure-classification provenance)
  "Construct one immutable operation-scoped visual observation."
  (%require-string :operation-id operation-id)
  (%require-string :run-id run-id)
  (%require-string :job-id job-id)
  (%require-string :asset-id asset-id)
  (%require-string :requested-url requested-url)
  (%require-string :final-url final-url)
  (%require-string :screenshot-evidence-ref screenshot-evidence-ref)
  (%require-string :screenshot-digest screenshot-digest)
  (%require-string :captured-at captured-at)
  (%require-duration-ms duration-ms)
  (%require-provenance provenance)
  (%require-optional-string :title title)
  (%validate-visual-evidence-http-status http-status)
  (%require-optional-string :client-profile-id client-profile-id)
  (%require-optional-string :browser-id browser-id)
  (%require-optional-string :browser-version browser-version)
  (%require-optional-string :body-digest body-digest)
  (%require-optional-string :capture-session-id capture-session-id)
  (%require-optional-string :exchange-id exchange-id)
  (%require-optional-string :failure-classification failure-classification)
  (%validate-visual-evidence-hints technology-hints)
  (when (and exchange-id (null capture-session-id))
    (error 'execution-graph-validation-error
           :field :capture-session-id
           :value capture-session-id
           :reason "exchange correlation requires capture session identity"))
  (%make-visual-evidence-record
   :operation-id operation-id
   :run-id run-id
   :job-id job-id
   :record-id (%record-id "visual-evidence" operation-id run-id job-id)
   :asset-id asset-id
   :requested-url requested-url
   :final-url final-url
   :screenshot-evidence-ref screenshot-evidence-ref
   :screenshot-digest screenshot-digest
   :captured-at captured-at
   :title title
   :http-status http-status
   :viewport viewport
   :client-profile-id client-profile-id
   :browser-id browser-id
   :browser-version browser-version
   :duration-ms duration-ms
   :body-digest body-digest
   :technology-hints (copy-list technology-hints)
   :capture-session-id capture-session-id
   :exchange-id exchange-id
   :failure-classification failure-classification
   :provenance provenance))

(defun visual-evidence-graph-name (operation-id)
  (%require-string :operation-id operation-id)
  (format nil "hackmode/visual-evidence/~A" (%key-part operation-id)))

(defun visual-evidence-record->tek9-node (record)
  (make-instance
   'tek9:node
   :id (visual-evidence-record-record-id record)
   :props (list
           :kind :visual-evidence
           :operation-id (visual-evidence-record-operation-id record)
           :run-id (visual-evidence-record-run-id record)
           :job-id (visual-evidence-record-job-id record)
           :asset-id (visual-evidence-record-asset-id record)
           :requested-url (visual-evidence-record-requested-url record)
           :final-url (visual-evidence-record-final-url record)
           :screenshot-evidence-ref
           (visual-evidence-record-screenshot-evidence-ref record)
           :screenshot-digest (visual-evidence-record-screenshot-digest record)
           :captured-at (visual-evidence-record-captured-at record)
           :title (visual-evidence-record-title record)
           :http-status (visual-evidence-record-http-status record)
           :viewport (visual-evidence-record-viewport record)
           :client-profile-id (visual-evidence-record-client-profile-id record)
           :browser-id (visual-evidence-record-browser-id record)
           :browser-version (visual-evidence-record-browser-version record)
           :duration-ms (visual-evidence-record-duration-ms record)
           :body-digest (visual-evidence-record-body-digest record)
           :technology-hints (copy-list (visual-evidence-record-technology-hints record))
           :capture-session-id (visual-evidence-record-capture-session-id record)
           :exchange-id (visual-evidence-record-exchange-id record)
           :failure-classification
           (visual-evidence-record-failure-classification record)
           :provenance (visual-evidence-record-provenance record))))

(defun tek9-node->visual-evidence-record (node)
  (let ((props (tek9:node-props node)))
    (unless (eq :visual-evidence (getf props :kind))
      (error 'execution-graph-validation-error
             :field :kind :value (getf props :kind)
             :reason "expected visual evidence node"))
    (let ((record
            (make-visual-evidence-record
             :operation-id (getf props :operation-id)
             :run-id (getf props :run-id)
             :job-id (getf props :job-id)
             :asset-id (getf props :asset-id)
             :requested-url (getf props :requested-url)
             :final-url (getf props :final-url)
             :screenshot-evidence-ref (getf props :screenshot-evidence-ref)
             :screenshot-digest (getf props :screenshot-digest)
             :captured-at (getf props :captured-at)
             :title (getf props :title)
             :http-status (getf props :http-status)
             :viewport (getf props :viewport)
             :client-profile-id (getf props :client-profile-id)
             :browser-id (getf props :browser-id)
             :browser-version (getf props :browser-version)
             :duration-ms (getf props :duration-ms)
             :body-digest (getf props :body-digest)
             :technology-hints (getf props :technology-hints)
             :capture-session-id (getf props :capture-session-id)
             :exchange-id (getf props :exchange-id)
             :failure-classification (getf props :failure-classification)
             :provenance (getf props :provenance))))
      (unless (string= (tek9:node-id node)
                       (visual-evidence-record-record-id record))
        (error 'execution-graph-validation-error
               :field :record-id :value (tek9:node-id node)
               :reason "stored visual evidence identity does not match typed identity"))
      record)))

(defun persist-visual-evidence-record
    (database record &key expected-operation-id expected-run-id)
  "Persist RECORD replay-safely through the canonical Tek9 graph boundary.
When EXPECTED-OPERATION-ID or EXPECTED-RUN-ID is supplied, reject records from
another scope before any canonical write occurs."
  (when expected-operation-id
    (%require-string :expected-operation-id expected-operation-id)
    (unless (string= expected-operation-id
                     (visual-evidence-record-operation-id record))
      (error 'execution-graph-validation-error
             :field :operation-id
             :value (visual-evidence-record-operation-id record)
             :reason "visual evidence write does not match expected operation scope")))
  (when expected-run-id
    (%require-string :expected-run-id expected-run-id)
    (unless (string= expected-run-id
                     (visual-evidence-record-run-id record))
      (error 'execution-graph-validation-error
             :field :run-id
             :value (visual-evidence-record-run-id record)
             :reason "visual evidence write does not match expected run scope")))
  (persist-graph-node-replay-safe
   database
   (visual-evidence-record->tek9-node record)
   :database-name
   (visual-evidence-graph-name (visual-evidence-record-operation-id record)))
  record)

(defun fetch-visual-evidence-record (database operation-id record-id)
  "Return one typed visual evidence record by stable RECORD-ID, or NIL."
  (%require-string :operation-id operation-id)
  (%require-string :record-id record-id)
  (let ((node (tek9:fetch-node
               database record-id
               :database-name (visual-evidence-graph-name operation-id))))
    (when node
      (let ((record (tek9-node->visual-evidence-record node)))
        (unless (string= operation-id
                         (visual-evidence-record-operation-id record))
          (error 'execution-graph-validation-error
                 :field :operation-id
                 :value (visual-evidence-record-operation-id record)
                 :reason "stored visual evidence does not match operation scope"))
        record))))

(defun fetch-visual-evidence-records (database operation-id &key run-id)
  "Return visual evidence for one operation in deterministic record-ID order."
  (%require-string :operation-id operation-id)
  (when run-id
    (%require-string :run-id run-id))
  (let ((records nil))
    (dolist (node (tek9:fetch-graph-nodes
                   database (visual-evidence-graph-name operation-id)))
      (when (eq :visual-evidence (getf (tek9:node-props node) :kind))
        (let ((record (tek9-node->visual-evidence-record node)))
          (unless (string= operation-id
                           (visual-evidence-record-operation-id record))
            (error 'execution-graph-validation-error
                   :field :operation-id
                   :value (visual-evidence-record-operation-id record)
                   :reason "stored visual evidence does not match operation scope"))
          (when (or (null run-id)
                    (string= run-id (visual-evidence-record-run-id record)))
            (push record records)))))
    (sort records #'string< :key #'visual-evidence-record-record-id)))