(in-package :hackmode-tests)

(defun run-expert-loop-tests ()
  (let* ((step
           (hackmode:make-expert-playbook-step
            :id "work"
            :success-next "done"
            :failure-next "work"))
         (done
           (hackmode:make-expert-playbook-step
            :id "done"
            :terminal :succeeded))
         (playbook
           (hackmode:make-expert-playbook
            :id "open-loop"
            :version "1"
            :entry-step "work"
            :steps (list step done)
            :stop-conditions
            (list
             (hackmode:make-expert-stop-condition :kind :goal-satisfied)
             (hackmode:make-expert-stop-condition :kind :budget-exhausted)
             (hackmode:make-expert-stop-condition :kind :policy-denied)
             (hackmode:make-expert-stop-condition :kind :no-viable-extension)
             (hackmode:make-expert-stop-condition :kind :explicit-stop))))
         (plan
           (hackmode:instantiate-expert-plan
            playbook
            :id "plan-loop"
            :operation "op-a"
            :run-id "run-1"
            :objective-id "objective-1"))
         (policy (hackmode:make-expert-loop-policy :non-progress-threshold 2))
         (state
           (hackmode:make-expert-loop-state
            :operation "op-a"
            :run-id "run-1"
            :strategy :symbolic)))
    (multiple-value-bind (decision next-state)
        (hackmode:expert-loop-next-decision
         state plan policy :progress-p nil :failure-p t)
      (assert-equal :continue
                    (hackmode:expert-loop-decision-kind decision)
                    "first symbolic miss retries")
      (assert-equal :symbolic
                    (hackmode:expert-loop-state-strategy next-state)
                    "first miss stays symbolic")
      (assert-equal 1
                    (hackmode:expert-loop-state-non-progress-count next-state)
                    "first miss is accumulated")
      (multiple-value-bind (escalation direct-state)
          (hackmode:expert-loop-next-decision
           next-state plan policy :progress-p nil :failure-p t)
        (assert-equal :escalate
                      (hackmode:expert-loop-decision-kind escalation)
                      "threshold escalates")
        (assert-equal :symbolic-stall
                      (hackmode:expert-loop-decision-reason escalation)
                      "escalation explains symbolic stall")
        (assert-equal :direct
                      (hackmode:expert-loop-state-strategy direct-state)
                      "escalation switches reasoning strategy only")
        (multiple-value-bind (resume resumed-state)
            (hackmode:expert-loop-next-decision
             direct-state plan policy :progress-p t :failure-p nil)
          (assert-equal :resume-symbolic
                        (hackmode:expert-loop-decision-kind resume)
                        "direct progress returns to symbolic")
          (assert-equal :symbolic
                        (hackmode:expert-loop-state-strategy resumed-state)
                        "symbolic steady state resumes")
          (assert-equal 0
                        (hackmode:expert-loop-state-non-progress-count resumed-state)
                        "progress clears non-progress count"))))
    (dolist (case `((:goal-satisfied :goal-satisfied (:goal-satisfied-p t))
                    (:budget-exhausted :budget-exhausted (:budget-exhausted-p t))
                    (:policy-denied :policy-denied (:policy-denied-p t))
                    (:no-viable-extension :no-viable-extension (:viable-extension-p nil))
                    (:explicit-stop :explicit-stop (:explicit-stop-p t))))
      (destructuring-bind (expected-reason condition-key args) case
        (declare (ignore condition-key))
        (multiple-value-bind (decision stopped-state)
            (apply #'hackmode:expert-loop-next-decision
                   state plan policy args)
          (assert-equal :stop
                        (hackmode:expert-loop-decision-kind decision)
                        "declared plan stop condition stops loop")
          (assert-equal expected-reason
                        (hackmode:expert-loop-decision-reason decision)
                        "stop reason is retained")
          (assert-equal :symbolic
                        (hackmode:expert-loop-state-strategy stopped-state)
                        "stopping does not mutate reasoning strategy"))))
    (let* ((goal
             (hackmode:make-expert-objective-clause
              :kind :goal :predicate "root" :arguments '(:uid 0)))
           (objective
             (hackmode:make-expert-objective
              :id "objective-1"
              :version "1"
              :clauses (list goal)
              :limits (list (hackmode:make-expert-objective-limit
                             :name "provider-actions" :maximum 1))
              :granted-capabilities '("http-probe")))
           (fresh-budget
             (hackmode:make-expert-budget-state
              objective :operation "op-a" :run-id "run-1"))
           (exhausted-budget
             (hackmode:expert-budget-consume
              fresh-budget "provider-actions" :amount 1)))
      (multiple-value-bind (decision next-state)
          (hackmode:expert-loop-next-budgeted-decision
           state plan policy fresh-budget
           :progress-p t :failure-p nil)
        (assert-equal :continue
                      (hackmode:expert-loop-decision-kind decision)
                      "available budget allows normal loop progress")
        (assert-equal :progress
                      (hackmode:expert-loop-state-last-reason next-state)
                      "budgeted decision preserves ordinary progress"))
      (multiple-value-bind (decision stopped-state)
          (hackmode:expert-loop-next-budgeted-decision
           state plan policy exhausted-budget
           :progress-p t :failure-p nil)
        (assert-equal :stop
                      (hackmode:expert-loop-decision-kind decision)
                      "exhausted objective budget stops declared plan")
        (assert-equal :budget-exhausted
                      (hackmode:expert-loop-decision-reason decision)
                      "budget stop reason is derived from typed budget state")
        (assert-equal :budget-exhausted
                      (hackmode:expert-loop-state-last-reason stopped-state)
                      "budget stop reason is retained in loop state"))
      (let ((wrong-scope
              (hackmode:make-expert-budget-state
               objective :operation "other-op" :run-id "run-1")))
        (handler-case
            (progn
              (hackmode:expert-loop-next-budgeted-decision
               state plan policy wrong-scope :progress-p t)
              (error "cross-operation budget state unexpectedly admitted"))
          (hackmode:invalid-expert-loop () t)))
      (let* ((other-goal
               (hackmode:make-expert-objective-clause
                :kind :goal :predicate "foothold" :arguments '(:required t)))
             (other-objective
               (hackmode:make-expert-objective
                :id "other-objective"
                :version "1"
                :clauses (list other-goal)
                :limits (list (hackmode:make-expert-objective-limit
                               :name "provider-actions" :maximum 1))
                :granted-capabilities '("http-probe")))
             (wrong-objective
               (hackmode:make-expert-budget-state
                other-objective :operation "op-a" :run-id "run-1")))
        (handler-case
            (progn
              (hackmode:expert-loop-next-budgeted-decision
               state plan policy wrong-objective :progress-p t)
              (error "cross-objective budget state unexpectedly admitted"))
          (hackmode:invalid-expert-loop () t))))
    (let ((active (hackmode:make-expert-engine :mode :active))
          (passive (hackmode:make-expert-engine :mode :passive)))
      (assert-equal :active
                    (hackmode:expert-engine-mode active)
                    "authority remains independent")
      (assert-equal :passive
                    (hackmode:expert-engine-mode passive)
                    "passive authority remains independent")
      (assert-equal :symbolic
                    (hackmode:expert-loop-state-strategy state)
                    "reasoning strategy does not encode authority"))
    (format t "Hackmode expert loop tests passed.~%")
    t))
