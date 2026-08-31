(in-package :hackmode-tests)

(defun run-expert-selection-tests ()
  (let* ((foothold
           (hackmode:make-expert-objective-clause
            :kind :precondition
            :predicate "foothold"
            :arguments '(:required t)))
         (root-goal
           (hackmode:make-expert-objective-clause
            :kind :goal
            :predicate "final_identity"
            :arguments '(:uid 0)))
         (proof
           (hackmode:make-expert-objective-clause
            :kind :evidence
            :predicate "authenticated_execution"
            :arguments '(:proves "final_identity")))
         (objective
           (hackmode:make-expert-objective
            :id "root-objective"
            :version "2"
            :clauses (list foothold root-goal proof)
            :granted-capabilities '("http-probe" "shell-command")))
         (root-extension
           (hackmode:make-expert-extension
            :id "root-path"
            :version "1"
            :objective-predicates '("final_identity")
            :required-capabilities '("shell-command")
            :authority :active
            :strategies '(:symbolic)))
         (recon-extension
           (hackmode:make-expert-extension
            :id "recon-path"
            :version "1"
            :objective-predicates '("foothold")
            :required-capabilities '("http-probe")
            :authority :passive
            :strategies '(:symbolic)))
         (registry
           (hackmode:register-expert-extension
            (hackmode:register-expert-extension
             (hackmode:make-expert-extension-registry)
             root-extension)
            recon-extension)))
    (let ((satisfied '("foothold")))
      (multiple-value-bind (evaluation selection)
          (hackmode:expert-select-extension
           registry objective
           :authority :active
           :strategy :symbolic
           :available-capabilities '("shell-command" "http-probe")
           :clause-satisfied-p
           (lambda (clause)
             (member (hackmode:expert-objective-clause-predicate clause)
                     satisfied
                     :test #'string=)))
        (assert-equal :in-progress
                      (hackmode:expert-objective-evaluation-status evaluation)
                      "unmet goal keeps objective in progress")
        (assert-equal '("authenticated_execution" "final_identity")
                      (mapcar #'hackmode:expert-objective-clause-predicate
                              (hackmode:expert-objective-evaluation-unsatisfied-clauses
                               evaluation))
                      "re-evaluation retains deterministic unmet clauses")
        (assert-equal "recon-path"
                      (hackmode:expert-extension-selection-selected-id selection)
                      "stable extension order decides among applicable candidates")
        (assert-equal "1"
                      (hackmode:expert-extension-selection-selected-version selection)
                      "selection retains selected extension version")
        (assert-equal :selected
                      (hackmode:expert-extension-selection-reason selection)
                      "selection explains successful choice")
        (assert-equal '("recon-path" "root-path")
                      (mapcar #'hackmode:expert-extension-candidate-id
                              (hackmode:expert-extension-selection-candidates selection))
                      "selection records every considered extension")
        (assert-equal :applicable
                      (hackmode:expert-extension-candidate-reason
                       (first (hackmode:expert-extension-selection-candidates selection)))
                      "accepted candidate records applicability")
        (assert-equal :applicable
                      (hackmode:expert-extension-candidate-reason
                       (second (hackmode:expert-extension-selection-candidates selection)))
                      "later applicable candidates remain visible for explanation")))
    (multiple-value-bind (evaluation selection)
        (hackmode:expert-select-extension
         registry objective
         :authority :passive
         :strategy :symbolic
         :available-capabilities '("http-probe")
         :clause-satisfied-p (constantly nil))
      (declare (ignore evaluation))
      (assert-equal "recon-path"
                    (hackmode:expert-extension-selection-selected-id selection)
                    "passive selection cannot choose active-only extension")
      (let ((root-candidate
              (find "root-path"
                    (hackmode:expert-extension-selection-candidates selection)
                    :key #'hackmode:expert-extension-candidate-id
                    :test #'string=)))
        (assert-equal :authority-denied
                      (hackmode:expert-extension-candidate-reason root-candidate)
                      "rejected candidate records authority reason")))
    (multiple-value-bind (evaluation selection)
        (hackmode:expert-select-extension
         registry objective
         :authority :active
         :strategy :symbolic
         :available-capabilities '("shell-command" "http-probe")
         :clause-satisfied-p (constantly t))
      (assert-equal :satisfied
                    (hackmode:expert-objective-evaluation-status evaluation)
                    "re-evaluation detects satisfied objective")
      (assert-equal nil
                    (hackmode:expert-extension-selection-selected-id selection)
                    "satisfied objective selects no extension")
      (assert-equal :objective-satisfied
                    (hackmode:expert-extension-selection-reason selection)
                    "satisfied objective explains stop selection"))
    (let* ((work
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
              :id "objective-loop"
              :version "1"
              :entry-step "work"
              :steps (list work done)
              :stop-conditions
              (list
               (hackmode:make-expert-stop-condition :kind :goal-satisfied)
               (hackmode:make-expert-stop-condition :kind :no-viable-extension))))
           (plan
             (hackmode:instantiate-expert-plan
              playbook
              :id "objective-plan"
              :operation "op-a"
              :run-id "run-a"
              :objective-id "root-objective"))
           (policy (hackmode:make-expert-loop-policy :non-progress-threshold 2))
           (state
             (hackmode:make-expert-loop-state
              :operation "op-a"
              :run-id "run-a"
              :strategy :symbolic))
           (satisfied '("foothold")))
      (flet ((satisfied-p (clause)
               (member (hackmode:expert-objective-clause-predicate clause)
                       satisfied
                       :test #'string=)))
        (multiple-value-bind (evaluation selection decision next-state)
            (hackmode:expert-objective-loop-step
             state plan policy registry objective
             :authority :active
             :available-capabilities '("shell-command" "http-probe")
             :clause-satisfied-p #'satisfied-p
             :progress-p t)
          (assert-equal :in-progress
                        (hackmode:expert-objective-evaluation-status evaluation)
                        "loop step evaluates current evidence")
          (assert-equal "recon-path"
                        (hackmode:expert-extension-selection-selected-id selection)
                        "loop step selects from current applicable extensions")
          (assert-equal :continue
                        (hackmode:expert-loop-decision-kind decision)
                        "unsatisfied objective continues after progress")
          (setf satisfied
                '("foothold" "final_identity" "authenticated_execution"))
          (multiple-value-bind (second-evaluation second-selection second-decision
                                second-state)
              (hackmode:expert-objective-loop-step
               next-state plan policy registry objective
               :authority :active
               :available-capabilities '("shell-command" "http-probe")
               :clause-satisfied-p #'satisfied-p
               :progress-p t)
            (assert-equal :satisfied
                          (hackmode:expert-objective-evaluation-status
                           second-evaluation)
                          "next loop step re-evaluates newly available evidence")
            (assert-equal :objective-satisfied
                          (hackmode:expert-extension-selection-reason
                           second-selection)
                          "satisfied objective bypasses extension execution")
            (assert-equal :stop
                          (hackmode:expert-loop-decision-kind second-decision)
                          "newly satisfied objective stops on the next iteration")
            (assert-equal :goal-satisfied
                          (hackmode:expert-loop-decision-reason second-decision)
                          "objective satisfaction supplies the typed stop reason")
            (assert-equal "op-a"
                          (hackmode:expert-loop-state-operation second-state)
                          "loop step preserves operation scope")))))
    t))
