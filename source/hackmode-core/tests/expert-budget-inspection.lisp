(in-package :hackmode-tests)

(defun run-expert-budget-inspection-tests ()
  (let* ((goal (hackmode:make-expert-objective-clause
                :kind :goal :predicate "root" :arguments '(:uid 0)))
         (objective (hackmode:make-expert-objective
                     :id "root-objective" :version "3"
                     :clauses (list goal)
                     :limits (list
                              (hackmode:make-expert-objective-limit
                               :name "provider-actions" :maximum 2)
                              (hackmode:make-expert-objective-limit
                               :name "model-steps" :maximum 4))
                     :granted-capabilities '("http-probe")))
         (fresh (hackmode:make-expert-budget-state
                 objective :operation "op-1" :run-id "run-1"))
         (used (hackmode:expert-budget-consume
                fresh "provider-actions" :amount 2))
         (inspection (hackmode:expert-budget-inspection used)))
    (assert-equal "root-objective"
                  (hackmode:expert-budget-inspection-objective-id inspection)
                  "budget inspection retains objective identity")
    (assert-equal "3"
                  (hackmode:expert-budget-inspection-objective-version inspection)
                  "budget inspection retains objective version")
    (assert-equal "op-1"
                  (hackmode:expert-budget-inspection-operation inspection)
                  "budget inspection retains operation scope")
    (assert-equal "run-1"
                  (hackmode:expert-budget-inspection-run-id inspection)
                  "budget inspection retains run scope")
    (assert-equal
     '((:name "model-steps" :limit 4 :used 0 :remaining 4 :exhausted nil)
       (:name "provider-actions" :limit 2 :used 2 :remaining 0 :exhausted t))
     (hackmode:expert-budget-inspection-entries inspection)
     "budget inspection exposes deterministic remaining allowance")
    (assert-equal t
                  (hackmode:expert-budget-inspection-exhausted-p inspection)
                  "inspection reports any exhausted objective budget")
    (let ((entries (hackmode:expert-budget-inspection-entries inspection)))
      (setf (getf (first entries) :name) "tampered"
            (getf (first entries) :remaining) 99)
      (assert-equal "model-steps"
                    (getf (first
                           (hackmode:expert-budget-inspection-entries inspection))
                          :name)
                    "inspection returns defensive budget-name copies")
      (assert-equal 4
                    (getf (first
                           (hackmode:expert-budget-inspection-entries inspection))
                          :remaining)
                    "inspection returns defensive entry copies"))
    t))
