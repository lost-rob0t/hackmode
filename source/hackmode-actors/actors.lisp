(in-package :hackmode-actors)

(defvar *ontology-actors* nil
  "Alist of actor name to live Sento actor for the ontology actor system.")

(defvar *ontology-actor-port* nil
  "Memoized star-sento-compat runtime port used to spawn ontology actors.")

(defvar *asset-resolver* nil
  "Function of one asset id returning the stored asset, or NIL.

The asset-monitor actor needs to resolve wire identities back to typed assets.
The default resolver uses the current operation database.")

(defvar *capture-service* nil
  "Current IPX capture service owned by the ontology capture supervisor.")

(defun ontology-runtime-port ()
  (or *ontology-actor-port*
      (setf *ontology-actor-port* (starsentocompat:make-sento-runtime-port))))

(defparameter *ontology-actor-dispatchers*
  '((:asset-monitor . :providers)
    (:outbox . :outbox)
    (:provider-dispatcher . :providers)
    (:capture-supervisor . :shared)
    (:replay . :providers)
    (:expert-advisor . :shared))
  "Dispatcher per ontology actor on the shared Hackmode Sento system.")

(defun %dispatch-for-actor (name)
  (let ((dispatcher (cdr (assoc (intern (string-upcase name) :keyword)
                                *ontology-actor-dispatchers*))))
    (when dispatcher
      (list :dispatcher dispatcher))))

(defun %sento-actor-name (name)
  (format nil "hackmode-ontology-~a" name))

(defun %wire-reply (result)
  "Reply to an ask caller through the star-lang sento compatibility port."
  (starsentocompat:sento-reply result))

(defun %payload-value (payload name)
  (cdr (assoc name payload :test #'string=)))

(defun %default-asset-resolver (asset-id)
  (when (and hackmode:*db* (tek9:db-is-open-p hackmode:*db*))
    (ignore-errors (tek9:fetch* hackmode:*db* asset-id))))
;;; --- Handler functions bound by the actor spec :handler identifiers ---------

(defun asset-monitor-receive (message)
  "Project discovered assets to StarIntel 0.10.1 and enqueue for ingest."
  (let ((type (ontology-wire-message-type message))
        (payload (ontology-wire-message-payload message)))
    (validate-ontology-message type payload)
    (let* ((asset-id (%payload-value payload "assetId"))
           (asset (when *asset-resolver*
                    (funcall *asset-resolver* asset-id)))
           (json (when asset (asset->starintel-json asset))))
      (cond
        ((and asset json)
         (tell-hackmode-actor
          :outbox
          (make-ontology-wire-message
           "hackmode/enqueue-document@1"
           (list (cons "json" json)
                 (cons "dtype" (getf (jsown:parse json) "dtype")))))
         (%wire-reply '((:ok . t))))
        (t
         (%wire-reply '((:ok . nil)
                        (:reason . "asset not projectable"))))))))

(defun outbox-receive (message)
  "Durably enqueue projected documents and drain the StarIntel outbox."
  (let ((type (ontology-wire-message-type message))
        (payload (ontology-wire-message-payload message)))
    (validate-ontology-message type payload)
    (cond
      ((string= type "hackmode/enqueue-document@1")
       ;; The core outbox consumes parsed jsown objects; the wire contract is
       ;; the canonical JSON string.
       (hackmode:enqueue-starintel-json
        hackmode:*db* (jsown:parse (%payload-value payload "json")))
       (%wire-reply '((:queued . t))))
      ((string= type "hackmode/drain-outbox@1")
       (hackmode:drain-outbox hackmode:*db*
                              (hackmode:make-starintel-http-transport))
       (%wire-reply
        (make-ontology-wire-message
         "hackmode/outbox-state@1"
         (list (cons "queued"
                     (length (hackmode:list-outbox-entries
                              hackmode:*db* :state :queued)))
               (cons "failed"
                     (length (hackmode:list-outbox-entries
                              hackmode:*db* :state :failed)))))))
      (t (error "Outbox actor cannot handle ~s" type)))))

(defun provider-dispatcher-receive (message)
  "Run one capability synchronously on the provider dispatcher pool."
  (let ((type (ontology-wire-message-type message))
        (payload (ontology-wire-message-payload message)))
    (validate-ontology-message type payload)
    (let* ((capability (%payload-value payload "capability"))
           (input (%payload-value payload "input"))
           (result (hackmode:run-capability capability input))
           (assets (hackmode:provider-job-result-assets result)))
      (dolist (asset assets)
        (tell-hackmode-actor
         :asset-monitor
         (make-ontology-wire-message
          "hackmode/asset-discovered@1"
          (list (cons "assetId" (hackmode:asset-deterministic-id asset))
                (cons "kind" (string-downcase
                              (symbol-name (hackmode:asset-kind asset))))))))
      (%wire-reply
       (make-ontology-wire-message
        "hackmode/provider-result@1"
        (list (cons "jobId" (hackmode:provider-job-result-id result))
              (cons "status" "succeeded")
              (cons "assets"
                    (mapcar #'hackmode:asset-deterministic-id assets))))))))

(defun capture-supervisor-receive (message)
  "Manage the operation-scoped IPX capture service lifecycle."
  (let ((type (ontology-wire-message-type message))
        (payload (ontology-wire-message-payload message)))
    (validate-ontology-message type payload)
    (cond
      ((string= type "hackmode/start-capture@1")
       (let* ((spec (%payload-value payload "spec"))
              (state (hackmode:start-capture-service
                      (%payload-value spec "operationId")
                      :endpoint (%payload-value spec "endpoint")
                      :spool-id (%payload-value spec "spoolId")
                      :spool-path (%payload-value spec "spoolPath"))))
         (setf *capture-service* state)
         (%wire-reply
          (make-ontology-wire-message
           "hackmode/capture-state@1"
           (list (cons "state" "running")
                 (cons "spoolPath" (%payload-value spec "spoolPath")))))))
      ((string= type "hackmode/stop-capture@1")
       (when *capture-service*
         (hackmode:stop-capture-service *capture-service*)
         (setf *capture-service* nil))
       (%wire-reply
        (make-ontology-wire-message
         "hackmode/capture-state@1"
         (list (cons "state" "stopped")))))
      (t (error "Capture supervisor cannot handle ~s" type)))))

(defun replay-receive (message)
  "Replay one IPX spool into the operation graph."
  (let ((type (ontology-wire-message-type message))
        (payload (ontology-wire-message-payload message)))
    (validate-ontology-message type payload)
    (let ((result
            (hackmode:replay-ipx-http-spool
             hackmode:*db*
             (%payload-value payload "spoolPath")
             :operation-id (%payload-value payload "operationId")
             :capture-session-id (%payload-value payload "captureSessionId")
             :source-id (%payload-value payload "sourceId"))))
      (%wire-reply
       `((:committed . ,(hackmode:ipx-replay-result-committed-count result))
         (:quarantined . ,(hackmode:ipx-replay-result-quarantine-count result)))))))

(defun expert-advisor-receive (message)
  "Answer advisory expert queries; never mutate operation state."
  (let ((type (ontology-wire-message-type message))
        (payload (ontology-wire-message-payload message)))
    (validate-ontology-message type payload)
    (let ((target (%payload-value payload "target")))
      (cond
        ((string= type "hackmode/classify-target@1")
         (%wire-reply
          `((:classification . ,(hackmode:expert-classify-target target)))))
        ((string= type "hackmode/recommend-capabilities@1")
         (let ((recommendations
                 (hackmode:expert-recommend-capabilities target)))
           (%wire-reply
            (mapcar
             (lambda (recommendation)
               (make-ontology-wire-message
                "hackmode/expert-recommendation@1"
                (list (cons "capability"
                            (string-downcase
                             (string
                              (hackmode:expert-recommendation-capability
                               recommendation))))
                      (cons "reason"
                            (format
                             nil
                             "provider ~a at priority ~a"
                             (hackmode:expert-recommendation-provider
                              recommendation)
                             (hackmode:expert-recommendation-priority
                              recommendation))))))
             recommendations))))
        (t (error "Expert advisor cannot handle ~s" type))))))

(defun %handler-for-actor (name)
  "Return the host handler function declared by the actor spec."
  (let ((handler-id (ontology-actor-handler name)))
    (cond
      ((string= handler-id "hackmode-actor-asset-monitor")
       #'asset-monitor-receive)
      ((string= handler-id "hackmode-actor-outbox")
       #'outbox-receive)
      ((string= handler-id "hackmode-actor-provider-dispatcher")
       #'provider-dispatcher-receive)
      ((string= handler-id "hackmode-actor-capture-supervisor")
       #'capture-supervisor-receive)
      ((string= handler-id "hackmode-actor-replay")
       #'replay-receive)
      ((string= handler-id "hackmode-actor-expert-advisor")
       #'expert-advisor-receive)
      (t
       (error 'ontology-error
              :message (format nil "no host handler registered for ~s"
                               handler-id))))))

;;; --- Actor system lifecycle -------------------------------------------------

(defun ensure-hackmode-ontology-actors (&key system)
  "Spawn every ontology actor onto the shared Hackmode Sento system.

Each actor is validated against the compiled ontology: the spec declares the
service identity, accepted/produced message types, restart policy, mailbox
bounds, and the host handler identifier. Returns an alist of name to actor."
  (let ((context (or system (hackmode:ensure-hackmode-actor-system))))
    (dolist (name (ontology-actor-names))
      (unless (assoc name *ontology-actors* :test #'string=)
        (let ((actor
                (apply #'starsentocompat:runtime-spawn
                       (ontology-runtime-port)
                       context
                       (%sento-actor-name name)
                       (%handler-for-actor name)
                       (%dispatch-for-actor name))))
          (push (cons name actor) *ontology-actors*))))
    *ontology-actors*))

(defun stop-hackmode-ontology-actors ()
  "Stop every ontology actor; the shared Sento system is left running."
  (dolist (entry *ontology-actors*)
    (ignore-errors
      (starsentocompat:runtime-stop (ontology-runtime-port)
                                    (hackmode:ensure-hackmode-actor-system)
                                    (cdr entry)
                                    :wait t)))
  (setf *ontology-actors* nil)
  t)

(defun hackmode-ontology-actor (name)
  "Return the live actor named NAME, or signal an error."
  (let ((normalized (string-downcase (string name))))
    (or (cdr (assoc normalized *ontology-actors* :test #'string=))
        (error 'ontology-error
               :message (format nil "ontology actor ~s is not running"
                                normalized)))))

(defun tell-hackmode-actor (name message)
  "Send MESSAGE to the ontology actor named NAME without waiting."
  (starsentocompat:runtime-tell (ontology-runtime-port)
                                (hackmode-ontology-actor name)
                                message))

(defun ask-hackmode-actor (name message &key (timeout 10) (poll 0.02))
  "Send MESSAGE to the ontology actor NAME and wait for the reply value."
  (let* ((port (ontology-runtime-port))
         (future (starsentocompat:runtime-ask port
                                              (hackmode-ontology-actor name)
                                              message
                                              :timeout timeout)))
    (loop :repeat (max 1 (floor timeout poll))
          :until (starsentocompat:sento-future-complete-p future)
          :do (sleep poll)
          :finally (return (starsentocompat:sento-future-result future)))))

(defun start-asset-projection-loop ()
  "Wire the asset event stream into the ontology asset-monitor actor.

Every discovered asset that has a StarIntel projection flows to the outbox
automatically. Idempotent: subscribing twice adds one handler."
  (unless *asset-resolver*
    (setf *asset-resolver* #'%default-asset-resolver))
  (let ((handler (make-instance 'nhooks:handler
                                :name 'asset-projection-event-handler
                                :fn #'asset-projection-event-handler)))
    (unless (find handler (nhooks:handlers hackmode:*asset-event-hook*)
                  :test (lambda (candidate existing)
                          (eq (nhooks:name candidate)
                              (nhooks:name existing))))
      (nhooks:add-hook hackmode:*asset-event-hook* handler)))
  t)

(defun asset-projection-event-handler (event)
  "Asset event hook that drives the ontology asset-monitor actor."
  (let ((asset (hackmode:asset-event-asset event)))
    (when (and asset (asset-starintel-supported-p asset)
               *ontology-actors*)
      (tell-hackmode-actor
       :asset-monitor
       (make-ontology-wire-message
        "hackmode/asset-discovered@1"
        (list (cons "assetId" (hackmode:asset-deterministic-id asset))
              (cons "kind" (string-downcase
                            (symbol-name (hackmode:asset-kind asset))))))))))
