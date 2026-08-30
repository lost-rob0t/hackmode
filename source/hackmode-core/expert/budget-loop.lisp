(in-package :hackmode)

(defun validate-expert-loop-budget-scope (state plan budget-state)
  "Require BUDGET-STATE to describe the exact loop/plan run and objective."
  (check-type state expert-loop-state)
  (check-type plan expert-plan)
  (check-type budget-state expert-budget-state)
  (unless (string= (expert-loop-state-operation state)
                   (expert-budget-state-operation budget-state))
    (reject-expert-loop budget-state
                        "budget operation ~s does not match loop operation ~s"
                        (expert-budget-state-operation budget-state)
                        (expert-loop-state-operation state)))
  (unless (string= (expert-loop-state-run-id state)
                   (expert-budget-state-run-id budget-state))
    (reject-expert-loop budget-state
                        "budget run ~s does not match loop run ~s"
                        (expert-budget-state-run-id budget-state)
                        (expert-loop-state-run-id state)))
  (unless (string= (expert-plan-objective-id plan)
                   (expert-budget-state-objective-id budget-state))
    (reject-expert-loop budget-state
                        "budget objective ~s does not match plan objective ~s"
                        (expert-budget-state-objective-id budget-state)
                        (expert-plan-objective-id plan)))
  budget-state)

(defun expert-loop-next-budgeted-decision
    (state plan policy budget-state
     &key goal-satisfied-p policy-denied-p (viable-extension-p t)
       explicit-stop-p progress-p failure-p)
  "Return the next loop decision with budget exhaustion derived from typed state.

The budget object is immutable admission data. This adapter validates that it
belongs to the exact operation, run, and objective before deriving exhaustion,
then delegates to the generic loop. It performs no effects."
  (check-type state expert-loop-state)
  (check-type plan expert-plan)
  (check-type policy expert-loop-policy)
  (validate-expert-loop-scope state plan)
  (validate-expert-loop-budget-scope state plan budget-state)
  (expert-loop-next-decision
   state plan policy
   :goal-satisfied-p goal-satisfied-p
   :budget-exhausted-p (expert-budget-exhausted-p budget-state)
   :policy-denied-p policy-denied-p
   :viable-extension-p viable-extension-p
   :explicit-stop-p explicit-stop-p
   :progress-p progress-p
   :failure-p failure-p))

(export '(expert-loop-next-budgeted-decision))
