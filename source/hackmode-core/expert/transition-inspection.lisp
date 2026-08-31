(in-package :hackmode)

(defstruct (expert-loop-transition-inspection-state
             (:constructor %make-expert-loop-transition-inspection-state
                 (&key raw-operation raw-run-id kind reason
                       from-strategy to-strategy
                       from-non-progress-count to-non-progress-count)))
  "Bounded operator-facing snapshot of one reasoning-strategy transition."
  (raw-operation nil :read-only t)
  (raw-run-id nil :read-only t)
  (kind nil :read-only t)
  (reason nil :read-only t)
  (from-strategy nil :read-only t)
  (to-strategy nil :read-only t)
  (from-non-progress-count 0 :read-only t)
  (to-non-progress-count 0 :read-only t))

(defun validate-expert-loop-transition-inspection (before decision after)
  (unless (string= (expert-loop-state-operation before)
                   (expert-loop-state-operation after))
    (reject-expert-loop
     after
     "transition operation ~s does not match previous operation ~s"
     (expert-loop-state-operation after)
     (expert-loop-state-operation before)))
  (unless (string= (expert-loop-state-run-id before)
                   (expert-loop-state-run-id after))
    (reject-expert-loop
     after
     "transition run ~s does not match previous run ~s"
     (expert-loop-state-run-id after)
     (expert-loop-state-run-id before)))
  (unless (member (expert-loop-decision-kind decision)
                  +expert-loop-decision-kinds+)
    (reject-expert-loop decision
                        "unsupported loop decision kind ~s"
                        (expert-loop-decision-kind decision)))
  (unless (eq (expert-loop-decision-strategy decision)
              (expert-loop-state-strategy after))
    (reject-expert-loop
     after
     "decision strategy ~s does not match next-state strategy ~s"
     (expert-loop-decision-strategy decision)
     (expert-loop-state-strategy after)))
  (unless (equal (expert-loop-decision-reason decision)
                 (expert-loop-state-last-reason after))
    (reject-expert-loop
     after
     "decision reason ~s does not match next-state reason ~s"
     (expert-loop-decision-reason decision)
     (expert-loop-state-last-reason after)))
  (let ((from (expert-loop-state-strategy before))
        (to (expert-loop-state-strategy after)))
    (ecase (expert-loop-decision-kind decision)
      (:continue
       (unless (eq from to)
         (reject-expert-loop decision
                             "continue decision cannot change strategy")))
      (:stop
       (unless (eq from to)
         (reject-expert-loop decision
                             "stop decision cannot change strategy")))
      (:escalate
       (unless (and (eq from :symbolic) (eq to :direct))
         (reject-expert-loop decision
                             "escalation must transition symbolic to direct")))
      (:resume-symbolic
       (unless (and (eq from :direct) (eq to :symbolic))
         (reject-expert-loop decision
                             "resume must transition direct to symbolic")))))
  t)

(defun expert-loop-transition-inspection (before decision after)
  "Return a pure bounded snapshot of one validated loop strategy transition."
  (check-type before expert-loop-state)
  (check-type decision expert-loop-decision)
  (check-type after expert-loop-state)
  (validate-expert-loop-transition-inspection before decision after)
  (%make-expert-loop-transition-inspection-state
   :raw-operation (copy-seq (expert-loop-state-operation before))
   :raw-run-id (copy-seq (expert-loop-state-run-id before))
   :kind (expert-loop-decision-kind decision)
   :reason (expert-loop-decision-reason decision)
   :from-strategy (expert-loop-state-strategy before)
   :to-strategy (expert-loop-state-strategy after)
   :from-non-progress-count (expert-loop-state-non-progress-count before)
   :to-non-progress-count (expert-loop-state-non-progress-count after)))

(defun expert-loop-transition-inspection-operation (inspection)
  (copy-seq
   (expert-loop-transition-inspection-state-raw-operation inspection)))

(defun expert-loop-transition-inspection-run-id (inspection)
  (copy-seq
   (expert-loop-transition-inspection-state-raw-run-id inspection)))

(defun expert-loop-transition-inspection-kind (inspection)
  (expert-loop-transition-inspection-state-kind inspection))

(defun expert-loop-transition-inspection-reason (inspection)
  (expert-loop-transition-inspection-state-reason inspection))

(defun expert-loop-transition-inspection-from-strategy (inspection)
  (expert-loop-transition-inspection-state-from-strategy inspection))

(defun expert-loop-transition-inspection-to-strategy (inspection)
  (expert-loop-transition-inspection-state-to-strategy inspection))

(defun expert-loop-transition-inspection-from-non-progress-count (inspection)
  (expert-loop-transition-inspection-state-from-non-progress-count inspection))

(defun expert-loop-transition-inspection-to-non-progress-count (inspection)
  (expert-loop-transition-inspection-state-to-non-progress-count inspection))

(export '(expert-loop-transition-inspection
          expert-loop-transition-inspection-operation
          expert-loop-transition-inspection-run-id
          expert-loop-transition-inspection-kind
          expert-loop-transition-inspection-reason
          expert-loop-transition-inspection-from-strategy
          expert-loop-transition-inspection-to-strategy
          expert-loop-transition-inspection-from-non-progress-count
          expert-loop-transition-inspection-to-non-progress-count))
