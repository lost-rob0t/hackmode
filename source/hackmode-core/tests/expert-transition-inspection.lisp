(in-package :hackmode-tests)

(defun run-expert-transition-inspection-tests ()
  (let* ((before
           (hackmode:make-expert-loop-state
            :operation "op-1"
            :run-id "run-1"
            :strategy :symbolic
            :non-progress-count 1
            :last-reason :symbolic-non-progress))
         (decision
           (hackmode:make-expert-loop-decision
            :kind :escalate
            :reason :symbolic-stall
            :strategy :direct))
         (after
           (hackmode:make-expert-loop-state
            :operation "op-1"
            :run-id "run-1"
            :strategy :direct
            :non-progress-count 2
            :last-reason :symbolic-stall))
         (inspection
           (hackmode:expert-loop-transition-inspection before decision after)))
    (assert-equal "op-1"
                  (hackmode:expert-loop-transition-inspection-operation inspection)
                  "transition inspection retains operation scope")
    (assert-equal "run-1"
                  (hackmode:expert-loop-transition-inspection-run-id inspection)
                  "transition inspection retains run scope")
    (assert-equal :escalate
                  (hackmode:expert-loop-transition-inspection-kind inspection)
                  "transition inspection exposes the loop decision")
    (assert-equal :symbolic-stall
                  (hackmode:expert-loop-transition-inspection-reason inspection)
                  "transition inspection exposes the decision reason")
    (assert-equal :symbolic
                  (hackmode:expert-loop-transition-inspection-from-strategy inspection)
                  "transition inspection exposes the previous strategy")
    (assert-equal :direct
                  (hackmode:expert-loop-transition-inspection-to-strategy inspection)
                  "transition inspection exposes the next strategy")
    (assert-equal 1
                  (hackmode:expert-loop-transition-inspection-from-non-progress-count
                   inspection)
                  "transition inspection exposes previous stall count")
    (assert-equal 2
                  (hackmode:expert-loop-transition-inspection-to-non-progress-count
                   inspection)
                  "transition inspection exposes next stall count")
    (let ((operation
            (hackmode:expert-loop-transition-inspection-operation inspection))
          (run-id
            (hackmode:expert-loop-transition-inspection-run-id inspection)))
      (setf (char operation 0) #\X
            (char run-id 0) #\X)
      (assert-equal "op-1"
                    (hackmode:expert-loop-transition-inspection-operation inspection)
                    "transition inspection returns a defensive operation copy")
      (assert-equal "run-1"
                    (hackmode:expert-loop-transition-inspection-run-id inspection)
                    "transition inspection returns a defensive run-id copy")))
  (let* ((before
           (hackmode:make-expert-loop-state
            :operation "op-1" :run-id "run-1" :strategy :direct))
         (decision
           (hackmode:make-expert-loop-decision
            :kind :resume-symbolic :reason :direct-progress :strategy :symbolic))
         (after
           (hackmode:make-expert-loop-state
            :operation "op-1" :run-id "run-1" :strategy :symbolic
            :last-reason :direct-progress))
         (inspection
           (hackmode:expert-loop-transition-inspection before decision after)))
    (assert-equal :resume-symbolic
                  (hackmode:expert-loop-transition-inspection-kind inspection)
                  "direct progress is inspectable as a return to symbolic")
    (assert-equal :direct
                  (hackmode:expert-loop-transition-inspection-from-strategy inspection)
                  "resume transition starts in direct strategy")
    (assert-equal :symbolic
                  (hackmode:expert-loop-transition-inspection-to-strategy inspection)
                  "resume transition returns to symbolic strategy"))
  (let* ((before
           (hackmode:make-expert-loop-state
            :operation "op-1" :run-id "run-1" :strategy :symbolic))
         (decision
           (hackmode:make-expert-loop-decision
            :kind :escalate :reason :symbolic-stall :strategy :direct))
         (wrong-scope
           (hackmode:make-expert-loop-state
            :operation "other-op" :run-id "run-1" :strategy :direct
            :last-reason :symbolic-stall))
         (wrong-strategy
           (hackmode:make-expert-loop-state
            :operation "op-1" :run-id "run-1" :strategy :symbolic
            :last-reason :symbolic-stall)))
    (assert-signals 'hackmode:invalid-expert-loop
                    (lambda ()
                      (hackmode:expert-loop-transition-inspection
                       before decision wrong-scope))
                    "transition inspection rejects cross-operation state")
    (assert-signals 'hackmode:invalid-expert-loop
                    (lambda ()
                      (hackmode:expert-loop-transition-inspection
                       before decision wrong-strategy))
                    "transition inspection rejects decision/state disagreement"))
  t)
