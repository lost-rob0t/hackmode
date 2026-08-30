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
  "Return a side-effect-free inspection snapshot for ENGINE and loop STATE.

Authority and reasoning strategy remain separate fields so shell/UI clients do
not accidentally treat a strategy transition as an authority change."
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
  "Pure operator-facing snapshot of one instantiated expert plan."
  (plan-id nil :read-only t)
  (objective-id nil :read-only t)
  (current-step-id nil :read-only t)
  (raw-required-capabilities nil :read-only t)
  (success-next nil :read-only t)
  (failure-next nil :read-only t)
  (terminal nil :read-only t)
  (raw-stop-conditions nil :read-only t))

(defun expert-plan-inspection (plan)
  "Return a side-effect-free snapshot of PLAN's current operator-visible state.

The snapshot exposes only plan structure already present in the canonical expert
plan object. It does not advance the plan, dispatch providers, or mutate state."
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
            #'string<
            :key #'symbol-name)))
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
  "Return a defensive copy of current-step capability requirements."
  (copy-list
   (expert-plan-inspection-state-raw-required-capabilities inspection)))

(defun expert-plan-inspection-success-next (inspection)
  (expert-plan-inspection-state-success-next inspection))

(defun expert-plan-inspection-failure-next (inspection)
  (expert-plan-inspection-state-failure-next inspection))

(defun expert-plan-inspection-terminal (inspection)
  (expert-plan-inspection-state-terminal inspection))

(defun expert-plan-inspection-stop-conditions (inspection)
  "Return a defensive copy of deterministically ordered stop-condition kinds."
  (copy-list (expert-plan-inspection-state-raw-stop-conditions inspection)))

(export '(expert-run-inspection
          expert-run-inspection-operation
          expert-run-inspection-run-id
          expert-run-inspection-authority
          expert-run-inspection-strategy
          expert-run-inspection-non-progress-count
          expert-run-inspection-last-reason
          expert-plan-inspection
          expert-plan-inspection-plan-id
          expert-plan-inspection-objective-id
          expert-plan-inspection-current-step-id
          expert-plan-inspection-required-capabilities
          expert-plan-inspection-success-next
          expert-plan-inspection-failure-next
          expert-plan-inspection-terminal
          expert-plan-inspection-stop-conditions))
