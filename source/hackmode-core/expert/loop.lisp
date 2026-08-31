(in-package :hackmode)

(defparameter +expert-reasoning-strategies+ '(:symbolic :direct)
  "Closed reasoning strategies for the generic Hackpert loop.")

(defparameter +expert-loop-decision-kinds+
  '(:continue :escalate :resume-symbolic :stop)
  "Closed decision vocabulary emitted by the generic Hackpert loop.")

(define-condition invalid-expert-loop (error)
  ((reason :initarg :reason :reader invalid-expert-loop-reason)
   (value :initarg :value :reader invalid-expert-loop-value))
  (:report (lambda (condition stream)
             (format stream "Invalid Hackpert loop state: ~a"
                     (invalid-expert-loop-reason condition)))))

(defun reject-expert-loop (value control &rest arguments)
  (error 'invalid-expert-loop
         :value value
         :reason (apply #'format nil control arguments)))

(defstruct (expert-loop-policy
             (:constructor %make-expert-loop-policy (&key non-progress-threshold)))
  (non-progress-threshold 2 :type integer))

(defun make-expert-loop-policy (&key (non-progress-threshold 2))
  (unless (plusp non-progress-threshold)
    (reject-expert-loop non-progress-threshold
                        "non-progress threshold must be a positive integer"))
  (%make-expert-loop-policy
   :non-progress-threshold non-progress-threshold))

(defstruct (expert-loop-state
             (:constructor %make-expert-loop-state
                 (&key operation run-id strategy non-progress-count last-reason))
             (:conc-name %expert-loop-state-))
  operation
  run-id
  (strategy :symbolic :type keyword)
  (non-progress-count 0 :type integer)
  last-reason)

(defun expert-loop-state-operation (state)
  "Return an independently mutable snapshot of STATE's operation scope."
  (check-type state expert-loop-state)
  (copy-seq (%expert-loop-state-operation state)))

(defun expert-loop-state-run-id (state)
  "Return an independently mutable snapshot of STATE's run scope."
  (check-type state expert-loop-state)
  (copy-seq (%expert-loop-state-run-id state)))

(defun expert-loop-state-strategy (state)
  (check-type state expert-loop-state)
  (%expert-loop-state-strategy state))

(defun expert-loop-state-non-progress-count (state)
  (check-type state expert-loop-state)
  (%expert-loop-state-non-progress-count state))

(defun expert-loop-state-last-reason (state)
  (check-type state expert-loop-state)
  (%expert-loop-state-last-reason state))

(defun make-expert-loop-state (&key operation run-id (strategy :symbolic)
                                    (non-progress-count 0) last-reason)
  (unless (expert-action-string-p operation)
    (reject-expert-loop operation "operation must be a non-empty string"))
  (unless (expert-action-string-p run-id)
    (reject-expert-loop run-id "run ID must be a non-empty string"))
  (unless (member strategy +expert-reasoning-strategies+)
    (reject-expert-loop strategy "unsupported reasoning strategy ~s" strategy))
  (unless (and (integerp non-progress-count) (not (minusp non-progress-count)))
    (reject-expert-loop non-progress-count
                        "non-progress count must be a non-negative integer"))
  (%make-expert-loop-state
   :operation (copy-seq operation)
   :run-id (copy-seq run-id)
   :strategy strategy
   :non-progress-count non-progress-count
   :last-reason last-reason))

(defstruct (expert-loop-decision
             (:constructor make-expert-loop-decision (&key kind reason strategy)))
  kind
  reason
  strategy)

(defun expert-loop-copy-state (state &key strategy non-progress-count last-reason)
  (%make-expert-loop-state
   :operation (copy-seq (%expert-loop-state-operation state))
   :run-id (copy-seq (%expert-loop-state-run-id state))
   :strategy (or strategy (%expert-loop-state-strategy state))
   :non-progress-count
   (if (null non-progress-count)
       (%expert-loop-state-non-progress-count state)
       non-progress-count)
   :last-reason last-reason))

(defun expert-loop-stop-reason (plan &key goal-satisfied-p budget-exhausted-p
                                          policy-denied-p (viable-extension-p t)
                                          explicit-stop-p)
  (loop for condition in
        (expert-playbook-stop-conditions (expert-plan-playbook plan))
        for kind = (expert-stop-condition-kind condition)
        when (expert-plan-stop-signal-p
              kind
              :goal-satisfied-p goal-satisfied-p
              :budget-exhausted-p budget-exhausted-p
              :policy-denied-p policy-denied-p
              :viable-extension-p viable-extension-p
              :explicit-stop-p explicit-stop-p)
          return kind))

(defun validate-expert-loop-scope (state plan)
  (unless (string= (%expert-loop-state-operation state)
                   (expert-plan-operation plan))
    (reject-expert-loop state
                        "loop operation ~s does not match plan operation ~s"
                        (%expert-loop-state-operation state)
                        (expert-plan-operation plan)))
  (unless (string= (%expert-loop-state-run-id state)
                   (expert-plan-run-id plan))
    (reject-expert-loop state
                        "loop run ~s does not match plan run ~s"
                        (%expert-loop-state-run-id state)
                        (expert-plan-run-id plan)))
  state)

(defun expert-loop-next-decision (state plan policy
                                  &key goal-satisfied-p budget-exhausted-p
                                    policy-denied-p (viable-extension-p t)
                                    explicit-stop-p progress-p failure-p)
  "Return the next pure loop decision and next loop state.

Reasoning strategy is independent of PASSIVE/ACTIVE authority. This function
never dispatches a provider, mutates canonical state, or invokes a model."
  (check-type state expert-loop-state)
  (check-type plan expert-plan)
  (check-type policy expert-loop-policy)
  (validate-expert-loop-scope state plan)
  (let ((stop-reason
          (expert-loop-stop-reason
           plan
           :goal-satisfied-p goal-satisfied-p
           :budget-exhausted-p budget-exhausted-p
           :policy-denied-p policy-denied-p
           :viable-extension-p viable-extension-p
           :explicit-stop-p explicit-stop-p)))
    (when stop-reason
      (return-from expert-loop-next-decision
        (values
         (make-expert-loop-decision
          :kind :stop
          :reason stop-reason
          :strategy (%expert-loop-state-strategy state))
         (expert-loop-copy-state state :last-reason stop-reason)))))
  (ecase (%expert-loop-state-strategy state)
    (:symbolic
     (cond
       (progress-p
        (values
         (make-expert-loop-decision
          :kind :continue :reason :progress :strategy :symbolic)
         (expert-loop-copy-state state
                                 :non-progress-count 0
                                 :last-reason :progress)))
       ((or failure-p (not progress-p))
        (let ((count (1+ (%expert-loop-state-non-progress-count state))))
          (if (>= count (expert-loop-policy-non-progress-threshold policy))
              (values
               (make-expert-loop-decision
                :kind :escalate
                :reason :symbolic-stall
                :strategy :direct)
               (expert-loop-copy-state state
                                       :strategy :direct
                                       :non-progress-count count
                                       :last-reason :symbolic-stall))
              (values
               (make-expert-loop-decision
                :kind :continue
                :reason :symbolic-non-progress
                :strategy :symbolic)
               (expert-loop-copy-state state
                                       :non-progress-count count
                                       :last-reason :symbolic-non-progress)))))))
    (:direct
     (if progress-p
         (values
          (make-expert-loop-decision
           :kind :resume-symbolic
           :reason :direct-progress
           :strategy :symbolic)
          (expert-loop-copy-state state
                                  :strategy :symbolic
                                  :non-progress-count 0
                                  :last-reason :direct-progress))
         (values
          (make-expert-loop-decision
           :kind :continue
           :reason (if failure-p :direct-failure :direct-non-progress)
           :strategy :direct)
          (expert-loop-copy-state
           state
           :strategy :direct
           :non-progress-count
           (1+ (%expert-loop-state-non-progress-count state))
           :last-reason (if failure-p :direct-failure :direct-non-progress)))))))

(export '(+expert-reasoning-strategies+
          +expert-loop-decision-kinds+
          invalid-expert-loop
          invalid-expert-loop-reason
          invalid-expert-loop-value
          expert-loop-policy
          make-expert-loop-policy
          expert-loop-policy-non-progress-threshold
          expert-loop-state
          make-expert-loop-state
          expert-loop-state-operation
          expert-loop-state-run-id
          expert-loop-state-strategy
          expert-loop-state-non-progress-count
          expert-loop-state-last-reason
          expert-loop-decision
          expert-loop-decision-kind
          expert-loop-decision-reason
          expert-loop-decision-strategy
          expert-loop-next-decision))
