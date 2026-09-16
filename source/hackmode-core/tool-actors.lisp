(in-package :hackmode)

(defparameter +hackmode-root-actor-name+ "hackmode")
(defparameter +hackmode-runtime-stream+ "hackmode/runtime")

(defun tool-actor-name (capability provider)
  "Return the stable Hackmode actor name for CAPABILITY/PROVIDER."
  (format nil "hackmode.tool.~a.~a"
          (canonical-tool-name capability)
          (canonical-tool-name provider)))

(defun tool-actor-stream-id (capability provider)
  (format nil "actor/~a" (tool-actor-name capability provider)))

(defun inferred-target-shape-for-provider (definition)
  (let ((input-type (capability-provider-input-type definition)))
    (cond
      ((eq input-type 'domain) 'domain)
      ((eq input-type 'host) 'host)
      ((eq input-type 'url) 'url)
      ((eq input-type 'tool-command-input) 'raw)
      (t 'raw))))

(defun effective-tool-mapping (definition)
  "Return explicit tool metadata or a non-mutating provider-derived fallback."
  (or (find-tool-mapping
       (capability-provider-capability definition)
       (capability-provider-name definition))
      (make-tool-mapping
       :capability (capability-provider-capability definition)
       :provider (capability-provider-name definition)
       :executable nil
       :target-shapes
       (list (canonical-tool-name
              (inferred-target-shape-for-provider definition)))
       :arguments nil
       :example-targets nil
       :platforms '("linux")
       :packages nil
       :fixed-arguments nil
       :metadata nil)))

(defun type-designator-name (value)
  (cond
    ((null value) nil)
    ((symbolp value) (string-downcase (symbol-name value)))
    (t (string-downcase (princ-to-string value)))))

(defun tool-argument-descriptor (argument)
  (list :name (string-downcase (symbol-name (tool-argument-name argument)))
        :type (type-designator-name (tool-argument-type argument))
        :required (tool-argument-required-p argument)
        :repeatable (tool-argument-repeatable-p argument)
        :default (tool-argument-default argument)
        :flag (tool-argument-flag argument)
        :description (tool-argument-description argument)))

(defun tool-target-shape-descriptor (shape)
  (list :name (tool-target-shape-name shape)
        :description (tool-target-shape-description shape)
        :examples (copy-tree (tool-target-shape-examples shape))
        :options
        (mapcar #'tool-argument-descriptor
                (tool-target-shape-options shape))))

(defun provider-output-type-names (definition)
  (mapcar #'type-designator-name
          (or (capability-provider-output-types definition) nil)))

(defun tool-actor-availability (definition mapping)
  (cond
    ((null definition) :unavailable)
    ((tool-mapping-available-p mapping) :online)
    (t :declared-offline)))

(defun tool-actor-descriptor-from-definition (definition)
  "Return a transport-neutral descriptor for one provider-backed tool actor."
  (let* ((mapping (effective-tool-mapping definition))
         (capability (capability-provider-capability definition))
         (provider (capability-provider-name definition)))
    (list
     :name (tool-actor-name capability provider)
     :kind :tool-actor
     :capability capability
     :provider provider
     :input-type
     (type-designator-name (capability-provider-input-type definition))
     :produces (provider-output-type-names definition)
     :target-shapes
     (mapcar (lambda (name)
               (tool-target-shape-descriptor
                (or (find-tool-target-shape name)
                    (error "Unknown target shape ~a." name))))
             (tool-mapping-target-shapes mapping))
     :arguments
     (mapcar #'tool-argument-descriptor
             (tool-mapping-arguments mapping))
     :example-targets
     (or (copy-tree (tool-mapping-example-targets mapping))
         (loop for shape-name in (tool-mapping-target-shapes mapping)
               for shape = (find-tool-target-shape shape-name)
               append (copy-list (and shape
                                      (tool-target-shape-examples shape)))))
     :executable (tool-mapping-executable mapping)
     :platforms (copy-list (tool-mapping-platforms mapping))
     :packages (copy-tree (tool-mapping-packages mapping))
     :availability (tool-actor-availability definition mapping)
     :metadata (copy-tree (tool-mapping-metadata mapping)))))

(defun list-tool-actor-descriptors ()
  "Return every currently registered provider as a stable tool-actor descriptor."
  (mapcar #'tool-actor-descriptor-from-definition
          (list-capability-providers)))

(defun find-tool-actor-definition-by-name (actor-name)
  (find actor-name
        (list-capability-providers)
        :test #'string=
        :key (lambda (definition)
               (tool-actor-name
                (capability-provider-capability definition)
                (capability-provider-name definition)))))

(defun describe-tool-actor (actor-name)
  "Return ACTOR-NAME's safe descriptor, or NIL."
  (let ((definition (find-tool-actor-definition-by-name actor-name)))
    (and definition
         (tool-actor-descriptor-from-definition definition))))

(defun tool-command-id (definition input)
  (starintel:digest-id
   "hackmode-tool-command-v1"
   (tool-actor-name
    (capability-provider-capability definition)
    (capability-provider-name definition))
   (provider-input-id (tool-command-input-target input))
   (tool-command-input-target-shape input)
   (with-standard-io-syntax
     (let ((*print-readably* t)
           (*print-pretty* nil))
       (prin1-to-string
        (list :arguments (tool-command-input-arguments input)
              :target-options (tool-command-input-target-options input)))))))

(defun terminal-tool-event-id (command-id terminal-type)
  (starintel:digest-id
   "hackmode-tool-command-terminal-v1"
   command-id
   (string-downcase (symbol-name terminal-type))))

(defun request-tool-event-id (command-id)
  (starintel:digest-id
   "hackmode-tool-command-request-v1"
   command-id))

(defun fetch-hackmode-actor-event (event-id
                                   &key (database *operations-database*))
  (let ((database (ensure-actor-event-databases database)))
    (tek9:fetch* database event-id :database-name +actor-event-records-db+)))

(defun existing-tool-terminal-result (command-id)
  (dolist (kind '(:completed :failed))
    (let ((event (fetch-hackmode-actor-event
                  (terminal-tool-event-id command-id kind))))
      (when event
        (return (copy-tree (getf (getf event :payload) :result)))))))

(defun unsupported-legacy-tool-options-p (definition input)
  (and (not (eq (capability-provider-input-type definition)
                'tool-command-input))
       (or (tool-command-input-arguments input)
           (tool-command-input-target-options input))))

(defun provider-input-for-tool-command (definition input)
  (if (eq (capability-provider-input-type definition) 'tool-command-input)
      input
      (tool-command-input-target input)))

(defun provider-job-result->tool-result (command-id result)
  (list
   :command-id command-id
   :job-id (provider-job-result-id result)
   :capability (provider-job-result-capability result)
   :provider (provider-job-result-provider result)
   :state (provider-job-result-state result)
   :created-count (provider-job-result-created-count result)
   :asset-ids
   (mapcar #'doc-id (provider-job-result-assets result))
   :error (provider-job-result-error result)
   :started-at (provider-job-result-started-at result)
   :finished-at (provider-job-result-finished-at result)))

(defun append-tool-request-event (definition mapping command-id input)
  (append-hackmode-actor-event
   (tool-actor-stream-id
    (capability-provider-capability definition)
    (capability-provider-name definition))
   :invocation-requested
   (list
    :actor (tool-actor-name
            (capability-provider-capability definition)
            (capability-provider-name definition))
    :command-id command-id
    :capability (capability-provider-capability definition)
    :provider (capability-provider-name definition)
    :target-shape (tool-command-input-target-shape input)
    :target-id (provider-input-id (tool-command-input-target input))
    :arguments (copy-tree (tool-command-input-arguments input))
    :target-options (copy-tree (tool-command-input-target-options input))
    :availability (tool-actor-availability definition mapping))
   :event-id (request-tool-event-id command-id)))

(defun append-tool-terminal-event (definition command-id result)
  (let ((kind (if (eq :succeeded (getf result :state))
                  :completed
                  :failed)))
    (append-hackmode-actor-event
     (tool-actor-stream-id
      (capability-provider-capability definition)
      (capability-provider-name definition))
     (if (eq kind :completed)
         :invocation-completed
         :invocation-failed)
     (list :command-id command-id
           :result (copy-tree result))
     :event-id (terminal-tool-event-id command-id kind))))

(defun make-tool-failure-result (definition command-id condition)
  (list
   :command-id command-id
   :job-id nil
   :capability (capability-provider-capability definition)
   :provider (capability-provider-name definition)
   :state :failed
   :created-count 0
   :asset-ids nil
   :error (princ-to-string condition)
   :started-at (unix-now)
   :finished-at (unix-now)))

(defun execute-tool-actor-request (definition target
                                   &key arguments target-options target-shape
                                     (database *db*))
  "Validate and execute one tool command with event-sourced idempotency."
  (let* ((mapping (effective-tool-mapping definition))
         (input
           (make-validated-tool-command-input
            mapping target
            :arguments arguments
            :target-options target-options
            :target-shape target-shape))
         (command-id (tool-command-id definition input))
         (existing (existing-tool-terminal-result command-id)))
    (when existing
      (return-from execute-tool-actor-request existing))
    (append-tool-request-event definition mapping command-id input)
    (let ((result
            (handler-case
                (progn
                  (unless (tool-mapping-available-p mapping)
                    (error "Tool executable ~a is unavailable on this host."
                           (tool-mapping-executable mapping)))
                  (when (unsupported-legacy-tool-options-p definition input)
                    (error
                     "Tool ~a does not accept actor argument/target options through its legacy provider contract."
                     (tool-actor-name
                      (capability-provider-capability definition)
                      (capability-provider-name definition))))
                  (unless (and database (tek9:db-is-open-p database))
                    (error "Tool execution requires an open Hackmode operation database."))
                  (provider-job-result->tool-result
                   command-id
                   (execute-provider-job
                    (capability-provider-capability definition)
                    (provider-input-for-tool-command definition input)
                    :provider (capability-provider-name definition)
                    :database database)))
              (condition (condition)
                (make-tool-failure-result definition command-id condition)))))
      (append-tool-terminal-event definition command-id result)
      result)))

(defun reply-tool-actor-caller (value &optional explicit-reply-to)
  (let ((reply-to (or explicit-reply-to sento.actor:*sender*)))
    (when reply-to
      (sento.actor:tell reply-to value)))
  value)

(defun tool-actor-handler (capability provider)
  (lambda (message)
    (destructuring-bind
        (command &key target arguments target-options target-shape reply-to)
        message
      (let ((definition (find-capability-provider capability provider)))
        (case command
          (:describe
           (reply-tool-actor-caller
            (and definition
                 (tool-actor-descriptor-from-definition definition))
            reply-to))
          (:invoke
           (unless definition
             (error "Tool provider ~a/~a is no longer registered."
                    capability provider))
           (reply-tool-actor-caller
            (execute-tool-actor-request
             definition target
             :arguments arguments
             :target-options target-options
             :target-shape target-shape)
            reply-to))
          (otherwise
           (error "Unknown Hackmode tool actor command: ~s" command)))))))

(defun ensure-tool-actor (definition &optional (system (ensure-hackmode-actor-system)))
  "Create the provider-backed tool actor if it is not already live."
  (let* ((capability (capability-provider-capability definition))
         (provider (capability-provider-name definition))
         (name (tool-actor-name capability provider))
         (existing (gethash name *tool-actors*)))
    (or existing
        (let ((actor
                (sento.actor-context:actor-of
                 system
                 :name name
                 :dispatcher :tools
                 :receive (tool-actor-handler capability provider))))
          (setf (gethash name *tool-actors*) actor)
          (append-hackmode-actor-event
           +hackmode-runtime-stream+
           :tool-actor-defined
           (tool-actor-descriptor-from-definition definition)
           :event-id
           (starintel:digest-id
            "hackmode-tool-actor-definition-v1"
            name
            capability
            provider))
          actor))))

(defun sync-tool-actors (&optional (system (ensure-hackmode-actor-system)))
  "Materialize one Sento actor for every currently registered capability provider."
  (dolist (definition (list-capability-providers))
    (ensure-tool-actor definition system))
  (list-tool-actor-descriptors))

(defun find-tool-actor (actor-name)
  "Return ACTOR-NAME's local Sento reference when currently materialized."
  (sync-tool-actors)
  (gethash actor-name *tool-actors*))

(defun dispatch-tool-actor (actor-name target
                            &key arguments target-options target-shape time-out)
  "Asynchronously ask ACTOR-NAME to execute a validated tool request."
  (let ((actor (or (find-tool-actor actor-name)
                   (error "Unknown Hackmode tool actor ~s." actor-name)))
        (message
          (list :invoke
                :target target
                :arguments arguments
                :target-options target-options
                :target-shape target-shape)))
    (if time-out
        (sento.actor:ask actor message :time-out time-out)
        (sento.actor:ask actor message))))

(defun root-tool-actor-handler ()
  (lambda (message)
    (destructuring-bind
        (command &key actor target arguments target-options target-shape stream-id reply-to)
        message
      (case command
        (:list-tools
         (sync-tool-actors)
         (reply-tool-actor-caller (list-tool-actor-descriptors) reply-to))
        (:describe-tool
         (reply-tool-actor-caller (describe-tool-actor actor) reply-to))
        (:invoke-tool
         (let ((tool-actor
                 (or (find-tool-actor actor)
                     (error "Unknown Hackmode tool actor ~s." actor))))
           (sento.actor:tell
            tool-actor
            (list :invoke
                  :target target
                  :arguments arguments
                  :target-options target-options
                  :target-shape target-shape
                  :reply-to (or reply-to sento.actor:*sender*)))
           tool-actor))
        (:refresh-tools
         (reply-tool-actor-caller (sync-tool-actors) reply-to))
        (:replay-events
         (reply-tool-actor-caller
          (replay-hackmode-actor-events (or stream-id +hackmode-runtime-stream+))
          reply-to))
        (:manifest
         (reply-tool-actor-caller
          (if (fboundp 'hackmode-actor-manifest)
              (hackmode-actor-manifest)
              nil)
          reply-to))
        (otherwise
         (error "Unknown Hackmode root actor command: ~s" command))))))

(defun start-hackmode-actor (&optional (system (ensure-hackmode-actor-system)))
  "Start Hackmode's root actor, materialize tool actors, and return the root ref."
  (unless *hackmode-actor*
    (setf *hackmode-actor*
          (sento.actor-context:actor-of
           system
           :name +hackmode-root-actor-name+
           :dispatcher :tools
           :receive (root-tool-actor-handler)))
    (append-hackmode-actor-event
     +hackmode-runtime-stream+
     :root-actor-defined
     (list :name +hackmode-root-actor-name+
           :kind :hackmode-actor)
     :event-id
     (starintel:digest-id
      "hackmode-root-actor-definition-v1"
      +hackmode-root-actor-name+)))
  (sync-tool-actors system)
  *hackmode-actor*)

(defun ask-hackmode-actor (message &key time-out)
  "Ask the root Hackmode actor MESSAGE and return Sento's future."
  (let ((actor (or *hackmode-actor* (start-hackmode-actor))))
    (if time-out
        (sento.actor:ask actor message :time-out time-out)
        (sento.actor:ask actor message))))

(nhooks:add-hook
 *startup-hook*
 (lambda ()
   (start-hackmode-actor)))
