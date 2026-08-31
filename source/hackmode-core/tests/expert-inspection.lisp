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
  (let* ((action
           (hackmode:make-expert-active-action
            :id "dispatch-1"
            :kind :dispatch
            :operation "op-1"
            :run-id "run-1"
            :expert-id "recon"
            :expert-version "3"
            :evidence-ids '("evidence-2" "evidence-1")
            :payload
            (hackmode:make-expert-dispatch-payload
             :capability "http-probe"
             :provider "curl"
             :input "https://secret.example/token=do-not-expose")))
         (status (hackmode:expert-action-inspection action)))
    (assert-equal "dispatch-1" (hackmode:expert-action-inspection-id status)
                  "action inspection retains action identity")
    (assert-equal :dispatch (hackmode:expert-action-inspection-kind status)
                  "action inspection exposes typed action kind")
    (assert-equal :provider-dispatch
                  (hackmode:expert-action-inspection-effect-kind status)
                  "action inspection exposes required effect class")
    (assert-equal "op-1" (hackmode:expert-action-inspection-operation status)
                  "action inspection retains operation scope")
    (assert-equal "run-1" (hackmode:expert-action-inspection-run-id status)
                  "action inspection retains run scope")
    (assert-equal "recon" (hackmode:expert-action-inspection-expert-id status)
                  "action inspection retains expert provenance")
    (assert-equal "3" (hackmode:expert-action-inspection-expert-version status)
                  "action inspection retains expert version")
    (assert-equal '("evidence-1" "evidence-2")
                  (hackmode:expert-action-inspection-evidence-ids status)
                  "action inspection normalizes evidence identity")
    (assert-equal '(:capability "http-probe" :provider "curl")
                  (hackmode:expert-action-inspection-summary status)
                  "dispatch inspection exposes bounded metadata only")
    (assert-equal nil
                  (search "do-not-expose"
                          (prin1-to-string
                           (hackmode:expert-action-inspection-summary status)))
                  "dispatch inspection never exposes provider input")
    (let ((evidence (hackmode:expert-action-inspection-evidence-ids status)))
      (setf (car evidence) "tampered")
      (assert-equal "evidence-1"
                    (first (hackmode:expert-action-inspection-evidence-ids status))
                    "action inspection returns defensive evidence copies")))
  (let* ((active (hackmode:make-expert-engine :mode :active))
         (passive (hackmode:make-expert-engine :mode :passive))
         (action
           (hackmode:make-expert-active-action
            :id "dispatch-admission-1"
            :kind :dispatch
            :operation "op-1"
            :run-id "run-1"
            :expert-id "recon"
            :expert-version "3"
            :evidence-ids '("evidence-1")
            :payload
            (hackmode:make-expert-dispatch-payload
             :capability "http-probe"
             :provider "curl"
             :input "https://secret.example/token=admission-do-not-expose")))
         (accepted
           (hackmode:expert-action-admission-inspection
            active action :operation "op-1" :run-id "run-1"))
         (denied
           (hackmode:expert-action-admission-inspection
            passive action :operation "op-1" :run-id "run-1"))
         (stale
           (hackmode:expert-action-admission-inspection
            active action :operation "other-op" :run-id "run-1")))
    (assert-equal :accepted
                  (hackmode:expert-action-admission-inspection-status accepted)
                  "matching active action is inspectably accepted")
    (assert-equal nil
                  (hackmode:expert-action-admission-inspection-rejection-kind accepted)
                  "accepted action has no rejection class")
    (assert-equal :rejected
                  (hackmode:expert-action-admission-inspection-status denied)
                  "passive dispatch is inspectably rejected")
    (assert-equal :effect-denied
                  (hackmode:expert-action-admission-inspection-rejection-kind denied)
                  "authority rejection is typed")
    (assert-equal :provider-dispatch
                  (hackmode:expert-action-admission-inspection-denied-effect denied)
                  "authority rejection exposes only the denied effect class")
    (assert-equal :rejected
                  (hackmode:expert-action-admission-inspection-status stale)
                  "cross-operation action is inspectably rejected")
    (assert-equal :invalid-action
                  (hackmode:expert-action-admission-inspection-rejection-kind stale)
                  "scope rejection is typed")
    (assert-equal t
                  (not (null
                        (search "does not match expected"
                                (hackmode:expert-action-admission-inspection-reason stale))))
                  "scope rejection retains a useful bounded reason")
    (dolist (inspection (list accepted denied stale))
      (assert-equal nil
                    (search "admission-do-not-expose"
                            (prin1-to-string inspection))
                    "admission inspection never exposes provider input")))
  t)
