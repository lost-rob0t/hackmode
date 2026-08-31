(in-package :hackmode-tests)

(defun run-expert-direct-candidate-tests ()
  (let* ((step (hackmode:make-expert-playbook-step
                :id "work"
                :success-next "done"
                :failure-next "work"))
         (done (hackmode:make-expert-playbook-step
                :id "done"
                :terminal :succeeded))
         (playbook (hackmode:make-expert-playbook
                    :id "direct-normalization"
                    :version "1"
                    :entry-step "work"
                    :steps (list step done)))
         (plan (hackmode:instantiate-expert-plan
                playbook
                :id "plan-direct"
                :operation "op-a"
                :run-id "run-1"
                :objective-id "objective-1"))
         (policy (hackmode:make-expert-loop-policy :non-progress-threshold 2))
         (direct-state (hackmode:make-expert-loop-state
                        :operation "op-a"
                        :run-id "run-1"
                        :strategy :direct))
         (payload (list :predicate "root-proven" :arguments (list :uid 0)))
         (candidate (hackmode:make-expert-direct-candidate
                     :operation "op-a"
                     :run-id "run-1"
                     :kind :evidence
                     :payload payload
                     :provenance (list :source "direct"))))
    (multiple-value-bind (decision next-state normalized)
        (hackmode:expert-loop-resume-with-direct-candidate
         direct-state plan policy candidate)
      (assert-equal :resume-symbolic
                    (hackmode:expert-loop-decision-kind decision)
                    "typed direct progress returns control to symbolic")
      (assert-equal :symbolic
                    (hackmode:expert-loop-state-strategy next-state)
                    "normalized direct progress resumes symbolic strategy")
      (assert-equal :evidence
                    (hackmode:expert-direct-candidate-kind normalized)
                    "candidate kind remains typed")
      (assert-equal "root-proven"
                    (getf (hackmode:expert-direct-candidate-payload normalized)
                          :predicate)
                    "candidate payload survives normalization"))
    (setf (getf payload :predicate) "mutated")
    (assert-equal "root-proven"
                  (getf (hackmode:expert-direct-candidate-payload candidate)
                        :predicate)
                  "candidate owns a defensive payload snapshot")
    (let ((operation (hackmode:expert-direct-candidate-operation candidate))
          (run-id (hackmode:expert-direct-candidate-run-id candidate))
          (exposed-payload (hackmode:expert-direct-candidate-payload candidate))
          (provenance (hackmode:expert-direct-candidate-provenance candidate)))
      (setf (char operation 0) #\X)
      (setf (char run-id 0) #\X)
      (setf (char (getf exposed-payload :predicate) 0) #\X)
      (setf (char (getf provenance :source) 0) #\X)
      (assert-equal "op-a"
                    (hackmode:expert-direct-candidate-operation candidate)
                    "candidate operation accessor returns a defensive string")
      (assert-equal "run-1"
                    (hackmode:expert-direct-candidate-run-id candidate)
                    "candidate run accessor returns a defensive string")
      (assert-equal "root-proven"
                    (getf (hackmode:expert-direct-candidate-payload candidate)
                          :predicate)
                    "candidate payload accessor returns a defensive snapshot")
      (assert-equal "direct"
                    (getf (hackmode:expert-direct-candidate-provenance candidate)
                          :source)
                    "candidate provenance accessor returns a defensive snapshot"))
    (handler-case
        (progn
          (hackmode:expert-loop-resume-with-direct-candidate
           direct-state plan policy
           (hackmode:make-expert-direct-candidate
            :operation "op-a"
            :run-id "other-run"
            :kind :plan
            :payload (list :id "candidate-plan")))
          (error "cross-run direct candidate unexpectedly admitted"))
      (hackmode:invalid-expert-direct-candidate () t))
    (handler-case
        (progn
          (hackmode:expert-loop-resume-with-direct-candidate
           (hackmode:make-expert-loop-state
            :operation "op-a" :run-id "run-1" :strategy :symbolic)
           plan policy candidate)
          (error "symbolic state unexpectedly accepted as direct normalization"))
      (hackmode:invalid-expert-direct-candidate () t))
    (format t "Hackmode expert direct candidate tests passed.~%")
    t))
