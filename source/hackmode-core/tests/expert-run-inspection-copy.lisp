(in-package :hackmode-tests)

(defun run-expert-run-inspection-copy-tests ()
  (let* ((engine (hackmode:make-expert-engine :mode :active))
         (reason (copy-seq "direct stalled"))
         (state (hackmode:make-expert-loop-state
                 :operation "op-1"
                 :run-id "run-1"
                 :strategy :direct
                 :non-progress-count 2
                 :last-reason reason))
         (inspection (hackmode:expert-run-inspection engine state))
         (returned (hackmode:expert-run-inspection-last-reason inspection)))
    (setf (char returned 0) #\X)
    (assert-equal "direct stalled"
                  (hackmode:expert-run-inspection-last-reason inspection)
                  "run inspection returns a defensive last-reason string"))
  t)
