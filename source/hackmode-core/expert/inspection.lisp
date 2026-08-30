(in-package :hackmode)

(defstruct (expert-run-inspection
             (:constructor %make-expert-run-inspection
                 (&key operation run-id authority strategy
                       non-progress-count last-reason)))
  "Pure operator-facing snapshot of one Hackpert run controller state."
  (operation nil :read-only t)
  (run-id nil :read-only t)
  (authority nil :read-only t)
  (strategy nil :read-only t)
  (non-progress-count 0 :read-only t)
  (last-reason nil :read-only t))

(defun expert-run-inspection (engine state)
  "Return a side-effect-free inspection snapshot for ENGINE and loop STATE."
  (check-type engine expert-engine)
  (check-type state expert-loop-state)
  (%make-expert-run-inspection
   :operation (expert-loop-state-operation state)
   :run-id (expert-loop-state-run-id state)
   :authority (expert-engine-mode engine)
   :strategy (expert-loop-state-strategy state)
   :non-progress-count (expert-loop-state-non-progress-count state)
   :last-reason (expert-loop-state-last-reason state)))

(defstruct (expert-plan-inspection-state
             (:constructor %make-expert-plan-inspection-state
                 (&key plan-id objective-id current-step-id
                       raw-required-capabilities success-next failure-next
                       terminal raw-stop-conditions)))
  (plan-id nil :read-only t)
  (objective-id nil :read-only t)
  (current-step-id nil :read-only t)
  (raw-required-capabilities nil :read-only t)
  (success-next nil :read-only t)
  (failure-next nil :read-only t)
  (terminal nil :read-only t)
  (raw-stop-conditions nil :read-only t))

(defun expert-plan-inspection (plan)
  "Return a side-effect-free snapshot of PLAN's current operator-visible state."
  (check-type plan expert-plan)
  (let* ((step (expert-plan-current-step plan))
         (capabilities
           (sort (copy-list (expert-playbook-step-required-capabilities step))
                 #'string<))
         (stop-conditions
           (sort
            (mapcar #'expert-stop-condition-kind
                    (expert-playbook-stop-conditions
                     (expert-plan-playbook plan)))
            #'string< :key #'symbol-name)))
    (%make-expert-plan-inspection-state
     :plan-id (expert-plan-id plan)
     :objective-id (expert-plan-objective-id plan)
     :current-step-id (expert-playbook-step-id step)
     :raw-required-capabilities capabilities
     :success-next (expert-playbook-step-success-next step)
     :failure-next (expert-playbook-step-failure-next step)
     :terminal (expert-playbook-step-terminal step)
     :raw-stop-conditions stop-conditions)))

(defun expert-plan-inspection-plan-id (inspection)
  (expert-plan-inspection-state-plan-id inspection))
(defun expert-plan-inspection-objective-id (inspection)
  (expert-plan-inspection-state-objective-id inspection))
(defun expert-plan-inspection-current-step-id (inspection)
  (expert-plan-inspection-state-current-step-id inspection))
(defun expert-plan-inspection-required-capabilities (inspection)
  (copy-list (expert-plan-inspection-state-raw-required-capabilities inspection)))
(defun expert-plan-inspection-success-next (inspection)
  (expert-plan-inspection-state-success-next inspection))
(defun expert-plan-inspection-failure-next (inspection)
  (expert-plan-inspection-state-failure-next inspection))
(defun expert-plan-inspection-terminal (inspection)
  (expert-plan-inspection-state-terminal inspection))
(defun expert-plan-inspection-stop-conditions (inspection)
  (copy-list (expert-plan-inspection-state-raw-stop-conditions inspection)))

(defstruct (expert-action-inspection-state
             (:constructor %make-expert-action-inspection-state
                 (&key id kind effect-kind operation run-id expert-id expert-version
                       raw-evidence-ids raw-summary)))
  (id nil :read-only t)
  (kind nil :read-only t)
  (effect-kind nil :read-only t)
  (operation nil :read-only t)
  (run-id nil :read-only t)
  (expert-id nil :read-only t)
  (expert-version nil :read-only t)
  (raw-evidence-ids nil :read-only t)
  (raw-summary nil :read-only t))

(defun expert-action-inspection-payload-summary (action)
  (let ((payload (expert-active-action-payload action)))
    (case (expert-active-action-kind action)
      (:dispatch
       (list :capability (expert-dispatch-payload-capability payload)
             :provider (expert-dispatch-payload-provider payload)))
      (:graph-delta
       (list :node-count (length (expert-graph-delta-payload-nodes payload))
             :edge-count (length (expert-graph-delta-payload-edges payload))))
      (:discover (list :asset-type (type-of (expert-discover-payload-asset payload))))
      (:operational-kb-delta
       (list :assertion-count (length (expert-kb-delta-payload-assertions payload))
             :retraction-count (length (expert-kb-delta-payload-retractions payload))))
      (:plan-transition
       (list :plan-id (expert-plan-transition-payload-plan-id payload)
             :step-id (expert-plan-transition-payload-step-id payload)
             :transition (expert-plan-transition-payload-transition payload)))
      (:control
       (list :directive (expert-control-payload-directive payload)
             :reason (expert-control-payload-reason payload))))))

(defun expert-action-inspection (action)
  "Return bounded metadata for ACTION without exposing raw effect payloads."
  (check-type action expert-active-action)
  (%make-expert-action-inspection-state
   :id (expert-active-action-id action)
   :kind (expert-active-action-kind action)
   :effect-kind (expert-active-action-effect-kind action)
   :operation (expert-active-action-operation action)
   :run-id (expert-active-action-run-id action)
   :expert-id (expert-active-action-expert-id action)
   :expert-version (expert-active-action-expert-version action)
   :raw-evidence-ids (sort (copy-list (expert-active-action-evidence-ids action)) #'string<)
   :raw-summary (expert-action-inspection-payload-summary action)))

(defun expert-action-inspection-id (x) (expert-action-inspection-state-id x))
(defun expert-action-inspection-kind (x) (expert-action-inspection-state-kind x))
(defun expert-action-inspection-effect-kind (x) (expert-action-inspection-state-effect-kind x))
(defun expert-action-inspection-operation (x) (expert-action-inspection-state-operation x))
(defun expert-action-inspection-run-id (x) (expert-action-inspection-state-run-id x))
(defun expert-action-inspection-expert-id (x) (expert-action-inspection-state-expert-id x))
(defun expert-action-inspection-expert-version (x) (expert-action-inspection-state-expert-version x))
(defun expert-action-inspection-evidence-ids (x)
  (copy-list (expert-action-inspection-state-raw-evidence-ids x)))
(defun expert-action-inspection-summary (x)
  (copy-tree (expert-action-inspection-state-raw-summary x)))

(export '(expert-run-inspection
          expert-run-inspection-operation expert-run-inspection-run-id
          expert-run-inspection-authority expert-run-inspection-strategy
          expert-run-inspection-non-progress-count expert-run-inspection-last-reason
          expert-plan-inspection expert-plan-inspection-plan-id
          expert-plan-inspection-objective-id expert-plan-inspection-current-step-id
          expert-plan-inspection-required-capabilities expert-plan-inspection-success-next
          expert-plan-inspection-failure-next expert-plan-inspection-terminal
          expert-plan-inspection-stop-conditions
          expert-action-inspection expert-action-inspection-id
          expert-action-inspection-kind expert-action-inspection-effect-kind
          expert-action-inspection-operation expert-action-inspection-run-id
          expert-action-inspection-expert-id expert-action-inspection-expert-version
          expert-action-inspection-evidence-ids expert-action-inspection-summary))
