(in-package :hackmode-tests)

(defun assert-invalid-expert-plan (thunk)
  (let ((condition nil))
    (handler-case
        (funcall thunk)
      (hackmode:invalid-expert-plan (raised)
        (setf condition raised)))
    (assert condition () "Expected HACKMODE:INVALID-EXPERT-PLAN.")
    condition))

(defun run-expert-plan-tests ()
  (let* ((enumerate
           (hackmode:make-expert-playbook-step
            :id "enumerate"
            :required-capabilities '("subdomain-enumerate")
            :success-next "probe"
            :failure-next "stop"))
         (probe
           (hackmode:make-expert-playbook-step
            :id "probe"
            :required-capabilities '("http-probe")
            :success-next "done"
            :failure-next "stop"))
         (done
           (hackmode:make-expert-playbook-step
            :id "done"
            :terminal :succeeded))
         (stop
           (hackmode:make-expert-playbook-step
            :id "stop"
            :terminal :failed))
         (playbook
           (hackmode:make-expert-playbook
            :id "generic-surface-expansion"
            :version "1"
            :entry-step "enumerate"
            :steps (list enumerate probe done stop)
            :stop-conditions
            (list
             (hackmode:make-expert-stop-condition :kind :budget-exhausted)
             (hackmode:make-expert-stop-condition :kind :policy-denied)
             (hackmode:make-expert-stop-condition :kind :no-viable-extension))))
         (plan
           (hackmode:instantiate-expert-plan
            playbook
            :id "plan-1"
            :operation "op-a"
            :run-id "run-1"
            :objective-id "objective-1")))
    (assert-equal "enumerate"
                  (hackmode:expert-plan-current-step-id plan)
                  "plan starts at playbook entry step")
    (assert-equal '("subdomain-enumerate")
                  (hackmode:expert-playbook-step-required-capabilities
                   (hackmode:expert-plan-current-step plan))
                  "current step exposes required capabilities")
    (assert-equal :continue
                  (hackmode:expert-plan-stop-decision
                   plan :budget-exhausted-p nil :policy-denied-p nil
                   :viable-extension-p t :goal-satisfied-p nil)
                  "plan continues while no stop condition is satisfied")
    (assert-equal :stop
                  (hackmode:expert-plan-stop-decision
                   plan :budget-exhausted-p t :policy-denied-p nil
                   :viable-extension-p t :goal-satisfied-p nil)
                  "budget exhaustion stops the plan")
    (let ((action
            (hackmode:expert-plan-transition-action
             plan
             :transition :advance
             :expert-id "planner"
             :expert-version "1"
             :evidence-ids '("result-1"))))
      (assert-equal :plan-transition
                    (hackmode:expert-active-action-kind action)
                    "plan transition is expressed through typed action protocol")
      (assert-equal "plan-1"
                    (hackmode:expert-plan-transition-payload-plan-id
                     (hackmode:expert-active-action-payload action))
                    "transition action retains plan identity")
      (assert-equal "enumerate"
                    (hackmode:expert-plan-transition-payload-step-id
                     (hackmode:expert-active-action-payload action))
                    "transition action retains current step identity"))
    (let ((next (hackmode:expert-plan-next-step-id plan :succeeded)))
      (assert-equal "probe" next "success branch is deterministic"))
    (let ((next (hackmode:expert-plan-next-step-id plan :failed)))
      (assert-equal "stop" next "failure branch is deterministic"))
    (assert-invalid-expert-plan
     (lambda ()
       (hackmode:make-expert-playbook
        :id "duplicate"
        :version "1"
        :entry-step "same"
        :steps (list
                (hackmode:make-expert-playbook-step :id "same" :terminal :succeeded)
                (hackmode:make-expert-playbook-step :id "same" :terminal :failed)))))
    (assert-invalid-expert-plan
     (lambda ()
       (hackmode:make-expert-playbook
        :id "dangling"
        :version "1"
        :entry-step "one"
        :steps (list
                (hackmode:make-expert-playbook-step
                 :id "one"
                 :success-next "missing"
                 :failure-next "one")))))
    (assert-invalid-expert-plan
     (lambda ()
       (hackmode:make-expert-playbook
        :id "terminal-with-branch"
        :version "1"
        :entry-step "done"
        :steps (list
                (hackmode:make-expert-playbook-step
                 :id "done"
                 :terminal :succeeded
                 :success-next "done")))))
    (format t "Hackmode expert plan tests passed.~%")
    t))
