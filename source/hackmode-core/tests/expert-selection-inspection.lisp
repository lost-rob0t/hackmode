(in-package :hackmode-tests)

(defun run-expert-selection-inspection-tests ()
  (let* ((precondition
           (hackmode:make-expert-objective-clause
            :kind :precondition
            :predicate "foothold"
            :arguments '(:required t :secret "do-not-expose")))
         (goal
           (hackmode:make-expert-objective-clause
            :kind :goal
            :predicate "final_identity"
            :arguments '(:uid 0)))
         (objective
           (hackmode:make-expert-objective
            :id "root-objective"
            :version "1"
            :clauses (list precondition goal)
            :limits nil
            :granted-capabilities '("http-probe")))
         (extension
           (hackmode:make-expert-extension
            :id "recon"
            :version "2"
            :objective-predicates '("foothold" "final_identity")
            :required-capabilities '("http-probe")
            :authority :passive
            :strategies '(:symbolic)))
         (registry
           (hackmode:register-expert-extension
            (hackmode:make-expert-extension-registry)
            extension)))
    (multiple-value-bind (evaluation selection)
        (hackmode:expert-select-extension
         registry objective
         :authority :active
         :strategy :symbolic
         :available-capabilities '("http-probe")
         :clause-satisfied-p
         (lambda (clause)
           (string= "final_identity"
                    (hackmode:expert-objective-clause-predicate clause))))
      (let ((inspection
              (hackmode:expert-objective-selection-inspection
               evaluation selection)))
        (assert-equal "root-objective"
                      (hackmode:expert-objective-selection-inspection-objective-id
                       inspection)
                      "selection inspection retains objective identity")
        (assert-equal "1"
                      (hackmode:expert-objective-selection-inspection-objective-version
                       inspection)
                      "selection inspection retains objective version")
        (assert-equal :blocked
                      (hackmode:expert-objective-selection-inspection-status inspection)
                      "selection inspection exposes objective status")
        (assert-equal '((:precondition "foothold"))
                      (hackmode:expert-objective-selection-inspection-blockers inspection)
                      "selection inspection exposes bounded unmet clause identity")
        (assert-equal :active
                      (hackmode:expert-objective-selection-inspection-authority inspection)
                      "selection inspection exposes authority independently")
        (assert-equal :symbolic
                      (hackmode:expert-objective-selection-inspection-strategy inspection)
                      "selection inspection exposes reasoning strategy independently")
        (assert-equal "recon"
                      (hackmode:expert-objective-selection-inspection-selected-id inspection)
                      "selection inspection exposes chosen extension")
        (assert-equal "2"
                      (hackmode:expert-objective-selection-inspection-selected-version inspection)
                      "selection inspection exposes chosen extension version")
        (assert-equal :selected
                      (hackmode:expert-objective-selection-inspection-reason inspection)
                      "selection inspection exposes selection reason")
        (assert-equal '(("recon" "2" :applicable))
                      (hackmode:expert-objective-selection-inspection-candidates inspection)
                      "selection inspection retains candidate decision provenance")
        (assert-equal nil
                      (search "do-not-expose" (prin1-to-string inspection))
                      "selection inspection never exposes objective clause arguments")
        (let ((blockers
                (hackmode:expert-objective-selection-inspection-blockers inspection))
              (candidates
                (hackmode:expert-objective-selection-inspection-candidates inspection)))
          (setf (caar blockers) :tampered
                (caar candidates) "tampered")
          (assert-equal '((:precondition "foothold"))
                        (hackmode:expert-objective-selection-inspection-blockers inspection)
                        "selection inspection returns defensive blocker copies")
          (assert-equal '(("recon" "2" :applicable))
                        (hackmode:expert-objective-selection-inspection-candidates inspection)
                        "selection inspection returns defensive candidate copies")))))
  t)
