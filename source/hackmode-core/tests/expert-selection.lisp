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
    t))
