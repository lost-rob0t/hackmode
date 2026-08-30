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
                  "inspection exposes last reasoning reason")
    t))
