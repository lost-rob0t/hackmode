(in-package :hackmode)

(defparameter +expert-plan-terminal-states+ '(:succeeded :failed)
  "Closed terminal states for a playbook step.")

(defparameter +expert-stop-condition-kinds+
  '(:goal-satisfied :budget-exhausted :policy-denied :no-viable-extension :explicit-stop)
  "Built-in stop signals understood by the generic plan substrate.")

(define-condition invalid-expert-plan (error)
  ((reason :initarg :reason :reader invalid-expert-plan-reason)
   (value :initarg :value :reader invalid-expert-plan-value))
  (:report (lambda (condition stream)
             (format stream "Invalid Hackpert plan/playbook: ~a"
                     (invalid-expert-plan-reason condition)))))

(defun reject-expert-plan (value control &rest arguments)
  (error 'invalid-expert-plan
         :value value
         :reason (apply #'format nil control arguments)))

(defstruct (expert-stop-condition
             (:constructor %make-expert-stop-condition (&key kind)))
  kind)

(defun make-expert-stop-condition (&key kind)
  (unless (member kind +expert-stop-condition-kinds+)
    (reject-expert-plan kind "unsupported stop condition ~s" kind))
  (%make-expert-stop-condition :kind kind))

(defstruct (expert-playbook-step
             (:constructor %make-expert-playbook-step
                 (&key id required-capabilities success-next failure-next terminal)))
  id
  (required-capabilities nil :type list)
  success-next
  failure-next
  terminal)

(defun make-expert-playbook-step (&key id required-capabilities
                                       success-next failure-next terminal)
  (unless (expert-action-string-p id)
    (reject-expert-plan id "step ID must be a non-empty string"))
  (unless (every #'expert-action-string-p required-capabilities)
    (reject-expert-plan required-capabilities
                        "required capabilities must be non-empty strings"))
  (when (and terminal (not (member terminal +expert-plan-terminal-states+)))
    (reject-expert-plan terminal "unsupported terminal state ~s" terminal))
  (when (and terminal (or success-next failure-next))
    (reject-expert-plan id "terminal step ~s cannot define branches" id))
  (unless (or terminal success-next failure-next)
    (reject-expert-plan id "non-terminal step ~s must define a branch" id))
  (dolist (next (list success-next failure-next))
    (unless (or (null next) (expert-action-string-p next))
      (reject-expert-plan next "branch target must be NIL or a non-empty string")))
  (%make-expert-playbook-step
   :id id
   :required-capabilities (copy-list required-capabilities)
   :success-next success-next
   :failure-next failure-next
   :terminal terminal))

(defstruct (expert-playbook
             (:constructor %make-expert-playbook
                 (&key id version entry-step steps stop-conditions)))
  id
  version
  entry-step
  (steps nil :type list)
  (stop-conditions nil :type list))

(defun expert-playbook-step-by-id (playbook step-id)
  (find step-id
        (expert-playbook-steps playbook)
        :key #'expert-playbook-step-id
        :test #'string=))

(defun validate-expert-playbook (playbook)
  (unless (expert-action-string-p (expert-playbook-id playbook))
    (reject-expert-plan playbook "playbook ID must be a non-empty string"))
  (unless (expert-action-string-p (expert-playbook-version playbook))
    (reject-expert-plan playbook "playbook version must be a non-empty string"))
  (unless (expert-action-string-p (expert-playbook-entry-step playbook))
    (reject-expert-plan playbook "entry step must be a non-empty string"))
  (unless (expert-playbook-steps playbook)
    (reject-expert-plan playbook "playbook requires at least one step"))
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (step (expert-playbook-steps playbook))
      (check-type step expert-playbook-step)
      (let ((id (expert-playbook-step-id step)))
        (when (gethash id seen)
          (reject-expert-plan playbook "duplicate step ID ~s" id))
        (setf (gethash id seen) t)))
    (unless (gethash (expert-playbook-entry-step playbook) seen)
      (reject-expert-plan playbook
                          "entry step ~s does not exist"
                          (expert-playbook-entry-step playbook)))
    (dolist (step (expert-playbook-steps playbook))
      (dolist (target (list (expert-playbook-step-success-next step)
                            (expert-playbook-step-failure-next step)))
        (when (and target (not (gethash target seen)))
          (reject-expert-plan playbook
                              "step ~s references missing branch target ~s"
                              (expert-playbook-step-id step)
                              target)))))
  (dolist (condition (expert-playbook-stop-conditions playbook))
    (check-type condition expert-stop-condition))
  playbook)

(defun make-expert-playbook (&key id version entry-step steps stop-conditions)
  (validate-expert-playbook
   (%make-expert-playbook
    :id id
    :version version
    :entry-step entry-step
    :steps (copy-list steps)
    :stop-conditions (copy-list stop-conditions))))

(defstruct (expert-plan
             (:constructor %make-expert-plan
                 (&key id operation run-id objective-id playbook current-step-id)))
  id
  operation
  run-id
  objective-id
  playbook
  current-step-id)

(defun instantiate-expert-plan (playbook &key id operation run-id objective-id)
  "Instantiate PLAYBOOK for one operation/run without mutating canonical state."
  (check-type playbook expert-playbook)
  (validate-expert-playbook playbook)
  (dolist (field (list (cons :id id)
                       (cons :operation operation)
                       (cons :run-id run-id)
                       (cons :objective-id objective-id)))
    (unless (expert-action-string-p (cdr field))
      (reject-expert-plan field "~a must be a non-empty string" (car field))))
  (%make-expert-plan
   :id id
   :operation operation
   :run-id run-id
   :objective-id objective-id
   :playbook playbook
   :current-step-id (expert-playbook-entry-step playbook)))

(defun expert-plan-current-step (plan)
  (check-type plan expert-plan)
  (or (expert-playbook-step-by-id
       (expert-plan-playbook plan)
       (expert-plan-current-step-id plan))
      (reject-expert-plan plan
                          "current step ~s is absent from playbook"
                          (expert-plan-current-step-id plan))))

(defun expert-plan-next-step-id (plan outcome)
  "Return the deterministic branch target for OUTCOME without applying it."
  (let ((step (expert-plan-current-step plan)))
    (when (expert-playbook-step-terminal step)
      (return-from expert-plan-next-step-id nil))
    (ecase outcome
      (:succeeded (expert-playbook-step-success-next step))
      (:failed (expert-playbook-step-failure-next step)))))

(defun expert-plan-stop-signal-p (kind &key goal-satisfied-p budget-exhausted-p
                                            policy-denied-p viable-extension-p
                                            explicit-stop-p)
  (ecase kind
    (:goal-satisfied goal-satisfied-p)
    (:budget-exhausted budget-exhausted-p)
    (:policy-denied policy-denied-p)
    (:no-viable-extension (not viable-extension-p))
    (:explicit-stop explicit-stop-p)))

(defun expert-plan-stop-decision (plan &key goal-satisfied-p budget-exhausted-p
                                            policy-denied-p (viable-extension-p t)
                                            explicit-stop-p)
  "Return :STOP when any declared playbook stop condition is satisfied.

The evaluator is intentionally generic. It consumes normalized signals supplied
by the objective/policy layer and does not hard-code a recon or exploitation
phase order."
  (check-type plan expert-plan)
  (if (some
       (lambda (condition)
         (expert-plan-stop-signal-p
          (expert-stop-condition-kind condition)
          :goal-satisfied-p goal-satisfied-p
          :budget-exhausted-p budget-exhausted-p
          :policy-denied-p policy-denied-p
          :viable-extension-p viable-extension-p
          :explicit-stop-p explicit-stop-p))
       (expert-playbook-stop-conditions (expert-plan-playbook plan)))
      :stop
      :continue))

(defun expert-plan-transition-action (plan &key transition expert-id expert-version
                                                evidence-ids)
  "Return a typed plan-transition action for PLAN's current step.

This function does not apply the transition. The existing active-action boundary
must admit it before any canonical plan-state mutation is performed."
  (check-type plan expert-plan)
  (make-expert-active-action
   :id (format nil "plan:~a:~a:~(~a~)"
               (expert-plan-id plan)
               (expert-plan-current-step-id plan)
               transition)
   :kind :plan-transition
   :operation (expert-plan-operation plan)
   :run-id (expert-plan-run-id plan)
   :expert-id expert-id
   :expert-version expert-version
   :evidence-ids evidence-ids
   :payload
   (make-expert-plan-transition-payload
    :plan-id (expert-plan-id plan)
    :step-id (expert-plan-current-step-id plan)
    :transition transition)))

(export '(+expert-plan-terminal-states+
          +expert-stop-condition-kinds+
          invalid-expert-plan
          invalid-expert-plan-reason
          invalid-expert-plan-value
          expert-stop-condition
          make-expert-stop-condition
          expert-stop-condition-kind
          expert-playbook-step
          make-expert-playbook-step
          expert-playbook-step-id
          expert-playbook-step-required-capabilities
          expert-playbook-step-success-next
          expert-playbook-step-failure-next
          expert-playbook-step-terminal
          expert-playbook
          make-expert-playbook
          expert-playbook-id
          expert-playbook-version
          expert-playbook-entry-step
          expert-playbook-steps
          expert-playbook-stop-conditions
          expert-playbook-step-by-id
          expert-plan
          instantiate-expert-plan
          expert-plan-id
          expert-plan-operation
          expert-plan-run-id
          expert-plan-objective-id
          expert-plan-playbook
          expert-plan-current-step-id
          expert-plan-current-step
          expert-plan-next-step-id
          expert-plan-stop-decision
          expert-plan-transition-action))
