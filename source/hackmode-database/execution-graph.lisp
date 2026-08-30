(in-package :hackmode-database)

(define-condition execution-graph-validation-error (error)
  ((field :initarg :field :reader execution-graph-error-field)
   (value :initarg :value :reader execution-graph-error-value)
   (reason :initarg :reason :reader execution-graph-error-reason))
  (:report (lambda (condition stream)
             (format stream "Invalid execution graph field ~S: ~A (~S)"
                     (execution-graph-error-field condition)
                     (execution-graph-error-reason condition)
                     (execution-graph-error-value condition)))))

(defstruct (execution-record (:constructor %make-execution-record))
  kind
  operation-id
  run-id
  call-id
  record-id
  capability-id
  status
  payload
  provenance)

(defun %non-empty-string-p (value)
  (and (stringp value) (plusp (length value))))

(defun %require-string (field value)
  (unless (%non-empty-string-p value)
    (error 'execution-graph-validation-error
           :field field :value value :reason "expected non-empty string"))
  value)

(defun %require-provenance (value)
  (unless value
    (error 'execution-graph-validation-error
           :field :provenance :value value :reason "provenance is required"))
  value)

(defun %require-http-port (value)
  (unless (and (integerp value) (<= 1 value 65535))
    (error 'execution-graph-validation-error
           :field :port :value value :reason "expected TCP port in range 1..65535"))
  value)

(defun %require-http-status (value)
  (unless (and (integerp value) (<= 100 value 599))
    (error 'execution-graph-validation-error
           :field :response-status :value value
           :reason "expected HTTP response status in range 100..599"))
  value)

(defun %require-duration-ms (value)
  (unless (and (integerp value) (not (minusp value)))
    (error 'execution-graph-validation-error
           :field :duration-ms :value value
           :reason "expected non-negative integer milliseconds"))
  value)

(defun %require-optional-string (field value)
  (when value
    (%require-string field value))
  value)

(defun %validate-http-exchange-payload (payload)
  (unless (listp payload)
    (error 'execution-graph-validation-error
           :field :payload :value payload :reason "expected HTTP exchange property list"))
  (%require-string :method (getf payload :method))
  (let ((scheme (getf payload :scheme)))
    (%require-string :scheme scheme)
    (unless (member scheme '("http" "https") :test #'string-equal)
      (error 'execution-graph-validation-error
             :field :scheme :value scheme :reason "expected http or https scheme")))
  (%require-string :host (getf payload :host))
  (%require-http-port (getf payload :port))
  (%require-string :path (getf payload :path))
  (%require-http-status (getf payload :response-status))
  (%require-optional-string :request-body-digest (getf payload :request-body-digest))
  (%require-optional-string :response-body-digest (getf payload :response-body-digest))
  (%require-string :raw-evidence-ref (getf payload :raw-evidence-ref))
  (%require-string :observed-at (getf payload :observed-at))
  (%require-duration-ms (getf payload :duration-ms))
  payload)

(defun %key-part (value)
  (let ((string (princ-to-string value)))
    (format nil "~D:~A" (length string) string)))

(defun %record-id (&rest parts)
  (with-output-to-string (stream)
    (dolist (part parts)
      (write-string (%key-part part) stream))))

(defun make-tool-call-record (&key operation-id run-id call-id capability-id input provenance)
  (%require-string :operation-id operation-id)
  (%require-string :run-id run-id)
  (%require-string :call-id call-id)
  (%require-string :capability-id capability-id)
  (%require-provenance provenance)
  (%make-execution-record
   :kind :tool-call
   :operation-id operation-id
   :run-id run-id
   :call-id call-id
   :record-id (%record-id "tool-call" operation-id run-id call-id)
   :capability-id capability-id
   :payload input
   :provenance provenance))

(defun make-tool-result-record
    (&key operation-id run-id call-id result-id status output provenance)
  (%require-string :operation-id operation-id)
  (%require-string :run-id run-id)
  (%require-string :call-id call-id)
  (%require-string :result-id result-id)
  (%require-provenance provenance)
  (unless (member status '(:succeeded :failed :cancelled :timed-out) :test #'eq)
    (error 'execution-graph-validation-error
           :field :status :value status :reason "unsupported tool result status"))
  (%make-execution-record
   :kind :tool-result
   :operation-id operation-id
   :run-id run-id
   :call-id call-id
   :record-id (%record-id "tool-result" operation-id run-id call-id result-id)
   :status status
   :payload output
   :provenance provenance))

(defun make-http-exchange-record
    (&key operation-id capture-session-id exchange-id method scheme host port path
          response-status request-body-digest response-body-digest raw-evidence-ref
          observed-at duration-ms provenance)
  "Construct one immutable HTTP exchange evidence record for the operation graph."
  (%require-string :operation-id operation-id)
  (%require-string :capture-session-id capture-session-id)
  (%require-string :exchange-id exchange-id)
  (%require-provenance provenance)
  (let ((payload (list :method method
                       :scheme scheme
                       :host host
                       :port port
                       :path path
                       :response-status response-status
                       :request-body-digest request-body-digest
                       :response-body-digest response-body-digest
                       :raw-evidence-ref raw-evidence-ref
                       :observed-at observed-at
                       :duration-ms duration-ms)))
    (%validate-http-exchange-payload payload)
    (%make-execution-record
     :kind :http-exchange
     :operation-id operation-id
     :run-id capture-session-id
     :call-id exchange-id
     :record-id (%record-id "http-exchange"
                            operation-id capture-session-id exchange-id)
     :payload payload
     :provenance provenance)))

(defun validate-tool-result-link (call result)
  (unless (eq :tool-call (execution-record-kind call))
    (error 'execution-graph-validation-error
           :field :call :value call :reason "expected tool-call record"))
  (unless (eq :tool-result (execution-record-kind result))
    (error 'execution-graph-validation-error
           :field :result :value result :reason "expected tool-result record"))
  (dolist (reader '(execution-record-operation-id execution-record-run-id execution-record-call-id))
    (unless (string= (funcall reader call) (funcall reader result))
      (error 'execution-graph-validation-error
             :field reader
             :value (list (funcall reader call) (funcall reader result))
             :reason "call/result identity mismatch")))
  t)

(defun execution-graph-name (operation-id)
  (%require-string :operation-id operation-id)
  (format nil "hackmode/execution/~A" (%key-part operation-id)))

(defun execution-record->tek9-node (record)
  (make-instance 'tek9:node
                 :id (execution-record-record-id record)
                 :props (list :kind (execution-record-kind record)
                              :operation-id (execution-record-operation-id record)
                              :run-id (execution-record-run-id record)
                              :call-id (execution-record-call-id record)
                              :capability-id (execution-record-capability-id record)
                              :status (execution-record-status record)
                              :payload (execution-record-payload record)
                              :provenance (execution-record-provenance record))))

(defun tek9-node->execution-record (node)
  "Reconstruct one typed execution record from a canonical Tek9 graph node."
  (let* ((props (tek9:node-props node))
         (kind (getf props :kind))
         (operation-id (getf props :operation-id))
         (run-id (getf props :run-id))
         (call-id (getf props :call-id))
         (capability-id (getf props :capability-id))
         (status (getf props :status))
         (payload (getf props :payload))
         (provenance (getf props :provenance)))
    (unless (member kind '(:tool-call :tool-result :http-exchange) :test #'eq)
      (error 'execution-graph-validation-error
             :field :kind :value kind :reason "unsupported stored execution record kind"))
    (%require-string :operation-id operation-id)
    (%require-string :run-id run-id)
    (%require-string :call-id call-id)
    (%require-string :record-id (tek9:node-id node))
    (%require-provenance provenance)
    (when (eq kind :tool-call)
      (%require-string :capability-id capability-id))
    (when (and (eq kind :tool-result)
               (not (member status '(:succeeded :failed :cancelled :timed-out) :test #'eq)))
      (error 'execution-graph-validation-error
             :field :status :value status :reason "unsupported stored tool result status"))
    (when (eq kind :http-exchange)
      (%validate-http-exchange-payload payload))
    (%make-execution-record
     :kind kind
     :operation-id operation-id
     :run-id run-id
     :call-id call-id
     :record-id (tek9:node-id node)
     :capability-id capability-id
     :status status
     :payload payload
     :provenance provenance)))

(defun tool-result-link-edge (call result)
  (validate-tool-result-link call result)
  (make-instance 'tek9:edge
                 :id (%record-id "tool-result-link"
                                 (execution-record-record-id call)
                                 (execution-record-record-id result))
                 :source (execution-record-record-id call)
                 :predicate :produced
                 :target (execution-record-record-id result)))
