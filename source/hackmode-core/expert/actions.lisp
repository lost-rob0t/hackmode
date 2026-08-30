(in-package :hackmode)

(defparameter +expert-active-action-kinds+
  '(:dispatch
    :graph-delta
    :discover
    :operational-kb-delta
    :plan-transition
    :control)
  "Closed first-version vocabulary for effect-bearing Hackpert actions.")

(defparameter +expert-plan-transitions+ '(:advance :fail :succeed)
  "Allowed state transitions for one Hackpert plan step.")

(defparameter +expert-control-directives+ '(:stop :yield :wait)
  "Allowed active-run control directives.")

(define-condition invalid-expert-action (error)
  ((reason :initarg :reason :reader invalid-expert-action-reason)
   (action :initarg :action :reader invalid-expert-action-action))
  (:report (lambda (condition stream)
             (format stream "Invalid Hackpert active action: ~a"
                     (invalid-expert-action-reason condition)))))

(defstruct expert-dispatch-payload
  capability
  provider
  input)

(defstruct expert-graph-delta-payload
  (nodes nil :type list)
  (edges nil :type list))

(defstruct expert-discover-payload
  asset)

(defstruct expert-kb-delta-payload
  (assertions nil :type list)
  (retractions nil :type list))

(defstruct expert-plan-transition-payload
  plan-id
  step-id
  transition)

(defstruct expert-control-payload
  directive
  reason)

(defstruct (expert-active-action
             (:constructor %make-expert-active-action
                 (&key id kind operation run-id expert-id expert-version
                       evidence-ids payload)))
  "Typed Hackpert request for one admitted active-run effect.

The action is only a request. Constructing or validating it never dispatches a
provider and never mutates canonical state. ACTION metadata is operation/run
scoped so the eventual executor can reject stale or cross-run output."
  id
  kind
  operation
  run-id
  expert-id
  expert-version
  (evidence-ids nil :type list)
  payload)

(defun expert-action-string-p (value)
  (and (stringp value) (plusp (length value))))

(defun invalid-expert-action (action control &rest arguments)
  (error 'invalid-expert-action
         :action action
         :reason (apply #'format nil control arguments)))

(defun validate-expert-action-metadata (action)
  (dolist (slot (list (cons :id (expert-active-action-id action))
                      (cons :operation (expert-active-action-operation action))
                      (cons :run-id (expert-active-action-run-id action))
                      (cons :expert-id (expert-active-action-expert-id action))
                      (cons :expert-version
                            (expert-active-action-expert-version action))))
    (unless (expert-action-string-p (cdr slot))
      (invalid-expert-action action "~a must be a non-empty string" (car slot))))
  (unless (every #'expert-action-string-p
                 (expert-active-action-evidence-ids action))
    (invalid-expert-action action
                           "evidence IDs must be non-empty strings"))
  action)

(defun validate-expert-dispatch-payload (action payload)
  (unless (expert-action-string-p
           (expert-dispatch-payload-capability payload))
    (invalid-expert-action action "dispatch capability is required"))
  (let ((provider (expert-dispatch-payload-provider payload)))
    (unless (or (null provider) (expert-action-string-p provider))
      (invalid-expert-action action
                             "dispatch provider must be NIL or a non-empty string")))
  (when (null (expert-dispatch-payload-input payload))
    (invalid-expert-action action "dispatch input is required"))
  payload)

(defun validate-expert-graph-delta-payload (action payload)
  (when (and (null (expert-graph-delta-payload-nodes payload))
             (null (expert-graph-delta-payload-edges payload)))
    (invalid-expert-action action "graph delta must contain nodes or edges"))
  payload)

(defun validate-expert-discover-payload (action payload)
  (when (null (expert-discover-payload-asset payload))
    (invalid-expert-action action "discover action requires an asset"))
  payload)

(defun validate-expert-kb-delta-payload (action payload)
  (when (and (null (expert-kb-delta-payload-assertions payload))
             (null (expert-kb-delta-payload-retractions payload)))
    (invalid-expert-action action
                           "operational KB delta must assert or retract data"))
  payload)

(defun validate-expert-plan-transition-payload (action payload)
  (unless (expert-action-string-p
           (expert-plan-transition-payload-plan-id payload))
    (invalid-expert-action action "plan transition requires a plan ID"))
  (unless (expert-action-string-p
           (expert-plan-transition-payload-step-id payload))
    (invalid-expert-action action "plan transition requires a step ID"))
  (unless (member (expert-plan-transition-payload-transition payload)
                  +expert-plan-transitions+)
    (invalid-expert-action action
                           "unsupported plan transition ~s"
                           (expert-plan-transition-payload-transition payload)))
  payload)

(defun validate-expert-control-payload (action payload)
  (unless (member (expert-control-payload-directive payload)
                  +expert-control-directives+)
    (invalid-expert-action action
                           "unsupported control directive ~s"
                           (expert-control-payload-directive payload)))
  (let ((reason (expert-control-payload-reason payload)))
    (unless (or (null reason) (stringp reason))
      (invalid-expert-action action "control reason must be NIL or a string")))
  payload)

(defun validate-expert-action-payload (action)
  (let ((kind (expert-active-action-kind action))
        (payload (expert-active-action-payload action)))
    (case kind
      (:dispatch
       (unless (typep payload 'expert-dispatch-payload)
         (invalid-expert-action action "dispatch requires dispatch payload"))
       (validate-expert-dispatch-payload action payload))
      (:graph-delta
       (unless (typep payload 'expert-graph-delta-payload)
         (invalid-expert-action action "graph-delta requires graph payload"))
       (validate-expert-graph-delta-payload action payload))
      (:discover
       (unless (typep payload 'expert-discover-payload)
         (invalid-expert-action action "discover requires discover payload"))
       (validate-expert-discover-payload action payload))
      (:operational-kb-delta
       (unless (typep payload 'expert-kb-delta-payload)
         (invalid-expert-action action
                                "operational-kb-delta requires KB payload"))
       (validate-expert-kb-delta-payload action payload))
      (:plan-transition
       (unless (typep payload 'expert-plan-transition-payload)
         (invalid-expert-action action
                                "plan-transition requires plan payload"))
       (validate-expert-plan-transition-payload action payload))
      (:control
       (unless (typep payload 'expert-control-payload)
         (invalid-expert-action action "control requires control payload"))
       (validate-expert-control-payload action payload))
      (otherwise
       (invalid-expert-action action "unsupported action kind ~s" kind)))))

(defun make-expert-active-action (&rest initargs &key &allow-other-keys)
  "Construct and validate one typed active action without executing it."
  (let ((action (apply #'%make-expert-active-action initargs)))
    (validate-expert-action-metadata action)
    (validate-expert-action-payload action)
    action))

(defun expert-active-action-effect-kind (action)
  "Return the Hackpert authority class required by ACTION."
  (check-type action expert-active-action)
  (case (expert-active-action-kind action)
    (:dispatch :provider-dispatch)
    ((:graph-delta :discover :operational-kb-delta :plan-transition)
     :canonical-mutation)
    (:control :active-control)
    (otherwise
     (invalid-expert-action action
                            "unsupported action kind ~s"
                            (expert-active-action-kind action)))))

(defun validate-expert-active-action (engine action &key operation run-id)
  "Admit ACTION for ENGINE and an expected operation/run identity.

This is the final pure boundary before a later executor. It proves authority,
shape, and provenance scope only. It intentionally performs zero effects."
  (check-type engine expert-engine)
  (check-type action expert-active-action)
  (validate-expert-action-metadata action)
  (validate-expert-action-payload action)
  (when (and operation
             (not (string= operation (expert-active-action-operation action))))
    (invalid-expert-action action
                           "operation ~s does not match expected ~s"
                           (expert-active-action-operation action)
                           operation))
  (when (and run-id
             (not (string= run-id (expert-active-action-run-id action))))
    (invalid-expert-action action
                           "run ~s does not match expected ~s"
                           (expert-active-action-run-id action)
                           run-id))
  (require-expert-engine-effect
   engine
   (expert-active-action-effect-kind action))
  action)

(export '(+expert-active-action-kinds+
          +expert-plan-transitions+
          +expert-control-directives+
          invalid-expert-action
          invalid-expert-action-reason
          invalid-expert-action-action
          expert-dispatch-payload
          make-expert-dispatch-payload
          expert-dispatch-payload-capability
          expert-dispatch-payload-provider
          expert-dispatch-payload-input
          expert-graph-delta-payload
          make-expert-graph-delta-payload
          expert-graph-delta-payload-nodes
          expert-graph-delta-payload-edges
          expert-discover-payload
          make-expert-discover-payload
          expert-discover-payload-asset
          expert-kb-delta-payload
          make-expert-kb-delta-payload
          expert-kb-delta-payload-assertions
          expert-kb-delta-payload-retractions
          expert-plan-transition-payload
          make-expert-plan-transition-payload
          expert-plan-transition-payload-plan-id
          expert-plan-transition-payload-step-id
          expert-plan-transition-payload-transition
          expert-control-payload
          make-expert-control-payload
          expert-control-payload-directive
          expert-control-payload-reason
          expert-active-action
          make-expert-active-action
          expert-active-action-id
          expert-active-action-kind
          expert-active-action-operation
          expert-active-action-run-id
          expert-active-action-expert-id
          expert-active-action-expert-version
          expert-active-action-evidence-ids
          expert-active-action-payload
          expert-active-action-effect-kind
          validate-expert-active-action))
