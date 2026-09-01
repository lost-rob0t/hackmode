(in-package :hackmode-tests)

(defun run-expert-selection-copy-tests ()
  (let* ((objective
           (hackmode:make-expert-objective
            :id "selection-copy-objective"
            :version "1"
            :clauses
            (list
             (hackmode:make-expert-objective-clause
              :kind :goal
              :predicate "copy_safe_goal"
              :arguments '(:required t)))
            :granted-capabilities '("http-probe")))
         (extension
           (hackmode:make-expert-extension
            :id "copy-safe-extension"
            :version "7"
            :objective-predicates '("copy_safe_goal")
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
         :authority :passive
         :strategy :symbolic
         :available-capabilities '("http-probe")
         :clause-satisfied-p (constantly nil))
      (declare (ignore evaluation))
      (let* ((candidate
               (first (hackmode:expert-extension-selection-candidates selection)))
             (candidate-id (hackmode:expert-extension-candidate-id candidate))
             (candidate-version
               (hackmode:expert-extension-candidate-version candidate))
             (selected-id
               (hackmode:expert-extension-selection-selected-id selection))
             (selected-version
               (hackmode:expert-extension-selection-selected-version selection)))
        (setf (char candidate-id 0) #\X
              (char candidate-version 0) #\9
              (char selected-id 0) #\Y
              (char selected-version 0) #\8)
        (assert-equal
         "copy-safe-extension"
         (hackmode:expert-extension-candidate-id candidate)
         "candidate ID accessor must not mutate stored selection provenance")
        (assert-equal
         "7"
         (hackmode:expert-extension-candidate-version candidate)
         "candidate version accessor must return a defensive identity snapshot")
        (assert-equal
         "copy-safe-extension"
         (hackmode:expert-extension-selection-selected-id selection)
         "candidate/accessor mutation must not rewrite selected extension identity")
        (assert-equal
         "7"
         (hackmode:expert-extension-selection-selected-version selection)
         "selected extension version accessor must return a defensive snapshot")))
    t))
