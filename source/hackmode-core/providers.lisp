(in-package :hackmode)

(defstruct capability-provider
  capability
  name
  input-type
  output-types
  handler
  (priority 100 :type integer))

(defstruct provider-invocation
  id
  capability
  provider
  input
  definition
  output
  state
  error
  started-at
  finished-at)

(defstruct provider-job-result
  id
  capability
  provider
  input
  assets
  (created-count 0 :type integer)
  state
  error
  started-at
  finished-at)

(defvar *capability-providers* (make-hash-table :test #'equal)
  "Registry of backend capability providers keyed by capability/provider name.")

(defun canonical-capability-name (value)
  (string-downcase (string value)))

(defun capability-provider-key (capability provider)
  (list (canonical-capability-name capability)
        (canonical-capability-name provider)))

(defun register-capability-provider (capability provider handler
                                     &key input-type output-types (priority 100))
  "Register HANDLER as PROVIDER for CAPABILITY and return its definition.

Provider handlers are backend functions. They consume a typed input object and
return either one typed Hackmode asset, a list of assets, or NIL. Persistence is
owned by the canonical provider completion path, never by the provider itself."
  (check-type handler function)
  (let ((definition
          (make-capability-provider
           :capability (canonical-capability-name capability)
           :name (canonical-capability-name provider)
           :input-type input-type
           :output-types output-types
           :handler handler
           :priority priority)))
    (setf (gethash (capability-provider-key capability provider)
                   *capability-providers*)
          definition)
    definition))

(defun unregister-capability-provider (capability provider)
  "Remove PROVIDER for CAPABILITY and return whether it existed."
  (remhash (capability-provider-key capability provider)
           *capability-providers*))

(defun clear-capability-providers ()
  "Clear the process-local provider registry. Primarily useful for clean tests."
  (clrhash *capability-providers*)
  t)

(defun list-capability-providers (&optional capability)
  "Return registered provider definitions, optionally limited to CAPABILITY."
  (let ((wanted (and capability (canonical-capability-name capability)))
        providers)
    (maphash
     (lambda (key definition)
       (declare (ignore key))
       (when (or (null wanted)
                 (string= wanted (capability-provider-capability definition)))
         (push definition providers)))
     *capability-providers*)
    (sort providers
          (lambda (left right)
            (or (< (capability-provider-priority left)
                   (capability-provider-priority right))
                (and (= (capability-provider-priority left)
                        (capability-provider-priority right))
                     (string< (capability-provider-name left)
                              (capability-provider-name right))))))))

(defun find-capability-provider (capability &optional provider)
  "Resolve CAPABILITY to an explicit PROVIDER or the highest-priority backend."
  (if provider
      (gethash (capability-provider-key capability provider)
               *capability-providers*)
      (first (list-capability-providers capability))))

(defun provider-input-id (input)
  "Return a stable identity component for typed provider INPUT."
  (if (typep input 'meta)
      (progn
        (normalize-asset input)
        (asset-deterministic-id input))
      (starintel:digest-id
       (with-output-to-string (stream)
         (prin1 input stream)))))

(defun provider-job-id (capability provider input)
  "Return the deterministic logical job ID for one provider invocation."
  (starintel:digest-id "hackmode-provider-job-v1"
                       (canonical-capability-name capability)
                       (canonical-capability-name provider)
                       (provider-input-id input)))

(defun provider-output-list (output)
  (cond
    ((null output) nil)
    ((listp output) output)
    (t (list output))))

(defun validate-provider-output (definition asset)
  (unless (typep asset 'meta)
    (error "Provider ~a returned non-Hackmode asset ~s."
           (capability-provider-name definition) asset))
  (let ((allowed (capability-provider-output-types definition)))
    (when (and allowed
               (notany (lambda (type) (typep asset type)) allowed))
      (error "Provider ~a returned asset type ~a outside declared outputs ~s."
             (capability-provider-name definition)
             (type-of asset)
             allowed)))
  asset)

(defun persist-provider-output (definition output database)
  "Persist provider OUTPUT through DISCOVER-ASSET and return assets/created count."
  (unless (and database (tek9:db-is-open-p database))
    (error "Provider execution requires an open operation database."))
  (let ((seen (make-hash-table :test #'equal))
        assets
        (created-count 0))
    (dolist (asset (provider-output-list output))
      (validate-provider-output definition asset)
      (multiple-value-bind (stored created-p)
          (discover-asset asset :database database)
        (when created-p
          (incf created-count))
        (unless (gethash (doc-id stored) seen)
          (setf (gethash (doc-id stored) seen) t)
          (push stored assets))))
    (values (nreverse assets) created-count)))

(defun invoke-provider (capability input &key provider (now (unix-now)))
  "Run one provider backend without mutating the operation store.

This phase is safe to execute concurrently in provider worker actors. Canonical
asset validation/persistence happens later in FINALIZE-PROVIDER-INVOCATION."
  (let* ((requested-provider (and provider (canonical-capability-name provider)))
         (definition (find-capability-provider capability provider))
         (provider-name (or (and definition (capability-provider-name definition))
                            requested-provider
                            "unresolved"))
         (job-id (provider-job-id capability provider-name input)))
    (handler-case
        (progn
          (unless definition
            (error "No provider registered for capability ~a~@[ backend ~a~]."
                   capability provider))
          (let ((input-type (capability-provider-input-type definition)))
            (when (and input-type (not (typep input input-type)))
              (error "Provider ~a requires input type ~s, got ~s."
                     provider-name input-type (type-of input))))
          (make-provider-invocation
           :id job-id
           :capability (capability-provider-capability definition)
           :provider provider-name
           :input input
           :definition definition
           :output (funcall (capability-provider-handler definition) input)
           :state :succeeded
           :error nil
           :started-at now
           :finished-at (unix-now)))
      (error (condition)
        (make-provider-invocation
         :id job-id
         :capability (canonical-capability-name capability)
         :provider provider-name
         :input input
         :definition definition
         :output nil
         :state :failed
         :error (format nil "~a" condition)
         :started-at now
         :finished-at (unix-now))))))

(defun failed-provider-job-result (invocation error)
  (make-provider-job-result
   :id (provider-invocation-id invocation)
   :capability (provider-invocation-capability invocation)
   :provider (provider-invocation-provider invocation)
   :input (provider-invocation-input invocation)
   :assets nil
   :created-count 0
   :state :failed
   :error error
   :started-at (provider-invocation-started-at invocation)
   :finished-at (unix-now)))

(defun finalize-provider-invocation (invocation database)
  "Convert INVOCATION into a persisted PROVIDER-JOB-RESULT.

Async callers route this function through the provider supervisor so all Tek9
writes are serialized even when backend workers execute concurrently."
  (if (eq :failed (provider-invocation-state invocation))
      (failed-provider-job-result invocation
                                  (provider-invocation-error invocation))
      (handler-case
          (multiple-value-bind (assets created-count)
              (persist-provider-output
               (provider-invocation-definition invocation)
               (provider-invocation-output invocation)
               database)
            (make-provider-job-result
             :id (provider-invocation-id invocation)
             :capability (provider-invocation-capability invocation)
             :provider (provider-invocation-provider invocation)
             :input (provider-invocation-input invocation)
             :assets assets
             :created-count created-count
             :state :succeeded
             :error nil
             :started-at (provider-invocation-started-at invocation)
             :finished-at (unix-now)))
        (error (condition)
          (failed-provider-job-result invocation (format nil "~a" condition))))))

(defun execute-provider-job (capability input
                             &key provider (database *db*) (now (unix-now)))
  "Execute one provider through the canonical invoke -> persist completion path."
  (finalize-provider-invocation
   (invoke-provider capability input :provider provider :now now)
   database))

(defun run-capability (capability input &key provider (database *db*))
  "Synchronously execute CAPABILITY through the canonical provider job path."
  (execute-provider-job capability input :provider provider :database database))
