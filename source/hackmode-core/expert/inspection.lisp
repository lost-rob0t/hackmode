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

(export '(expert-run-inspection
          expert-run-inspection-operation
          expert-run-inspection-run-id
          expert-run-inspection-authority
          expert-run-inspection-strategy
          expert-run-inspection-non-progress-count
          expert-run-inspection-last-reason))
