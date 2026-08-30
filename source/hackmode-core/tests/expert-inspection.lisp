(in-package :hackmode-tests)

(defun run-expert-inspection-tests ()
  (let* ((engine (hackmode:make-expert-engine :mode :active))
         (state (hackmode:make-expert-loop-state
                 :operation "op-1" :run-id "run-1"
                 :strategy :direct :non-progress-count 3
                 :last-reason :direct-non-progress))
         (status (hackmode:expert-run-inspection engine state)))
    (assert-equal "op-1" (hackmode:expert-run-inspection-operation status)
                  "inspection retains operation")
    (assert-equal "run-1" (hackmode:expert-run-inspection-run-id status)
                  "inspection retains run identity")
    (assert-equal :active (hackmode:expert-run-inspection-authority status)
                  "inspection exposes authority independently")
    (assert-equal :direct (hackmode:expert-run-inspection-strategy status)
                  "inspection exposes reasoning strategy independently")
    (assert-equal 3 (hackmode:expert-run-inspection-non-progress-count status)
                  "inspection exposes stall count")
    (assert-equal :direct-non-progress
                  (hackmode:expert-run-inspection-last-reason status)
                  "inspection exposes last reasoning reason"))
  (let* ((scan
           (hackmode:make-expert-playbook-step
            :id "scan"
            :required-capabilities '("http-probe" "subdomain-enumerate")
            :success-next "done"
            :failure-next "scan"))
         (done
           (hackmode:make-expert-playbook-step
            :id "done" :terminal :succeeded))
         (playbook
           (hackmode:make-expert-playbook
            :id "recon-plan"
            :version "2"
            :entry-step "scan"
            :steps (list scan done)
            :stop-conditions
            (list
             (hackmode:make-expert-stop-condition :kind :goal-satisfied)
             (hackmode:make-expert-stop-condition :kind :budget-exhausted))))
         (plan
           (hackmode:instantiate-expert-plan
            playbook
            :id "plan-1"
            :operation "op-1"
            :run-id "run-1"
            :objective-id "objective-1"))
         (status (hackmode:expert-plan-inspection plan)))
    (assert-equal "plan-1" (hackmode:expert-plan-inspection-plan-id status)
                  "plan inspection retains plan identity")
    (assert-equal "objective-1"
                  (hackmode:expert-plan-inspection-objective-id status)
                  "plan inspection retains objective identity")
    (assert-equal "scan" (hackmode:expert-plan-inspection-current-step-id status)
                  "plan inspection exposes current step")
    (assert-equal '("http-probe" "subdomain-enumerate")
                  (hackmode:expert-plan-inspection-required-capabilities status)
                  "plan inspection exposes current step capabilities")
    (assert-equal "done" (hackmode:expert-plan-inspection-success-next status)
                  "plan inspection exposes success branch")
    (assert-equal "scan" (hackmode:expert-plan-inspection-failure-next status)
                  "plan inspection exposes failure branch")
    (assert-equal nil (hackmode:expert-plan-inspection-terminal status)
                  "plan inspection exposes terminal state")
    (assert-equal '(:budget-exhausted :goal-satisfied)
                  (hackmode:expert-plan-inspection-stop-conditions status)
                  "plan inspection normalizes stop conditions deterministically")
    (let ((capabilities
            (hackmode:expert-plan-inspection-required-capabilities status))
          (conditions
            (hackmode:expert-plan-inspection-stop-conditions status)))
      (setf (car capabilities) "tampered"
            (car conditions) :tampered)
      (assert-equal "http-probe"
                    (first
                     (hackmode:expert-plan-inspection-required-capabilities status))
                    "plan inspection returns defensive capability copies")
      (assert-equal :budget-exhausted
                    (first (hackmode:expert-plan-inspection-stop-conditions status))
                    "plan inspection returns defensive stop-condition copies")))
  t)
