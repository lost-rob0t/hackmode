(in-package :hackmode-tests)

(defun run-expert-loop-scope-copy-tests ()
  (let* ((operation (copy-seq "op-a"))
         (run-id (copy-seq "run-1"))
         (last-reason (copy-seq "symbolic-stall"))
         (state
           (hackmode:make-expert-loop-state
            :operation operation
            :run-id run-id
            :strategy :symbolic
            :last-reason last-reason)))
    (setf (char operation 0) #\X
          (char run-id 0) #\X
          (char last-reason 0) #\X)
    (assert-equal "op-a"
                  (hackmode:expert-loop-state-operation state)
                  "loop state owns an operation-scope snapshot")
    (assert-equal "run-1"
                  (hackmode:expert-loop-state-run-id state)
                  "loop state owns a run-scope snapshot")
    (assert-equal "symbolic-stall"
                  (hackmode:expert-loop-state-last-reason state)
                  "loop state owns a mutable last-reason snapshot")
    (let ((exposed-operation (hackmode:expert-loop-state-operation state))
          (exposed-run-id (hackmode:expert-loop-state-run-id state))
          (exposed-last-reason (hackmode:expert-loop-state-last-reason state)))
      (setf (char exposed-operation 0) #\Y
            (char exposed-run-id 0) #\Y
            (char exposed-last-reason 0) #\Y)
      (assert-equal "op-a"
                    (hackmode:expert-loop-state-operation state)
                    "operation accessor does not expose mutable scope storage")
      (assert-equal "run-1"
                    (hackmode:expert-loop-state-run-id state)
                    "run accessor does not expose mutable scope storage")
      (assert-equal "symbolic-stall"
                    (hackmode:expert-loop-state-last-reason state)
                    "last-reason accessor does not expose mutable state storage"))
    (format t "Hackmode expert loop scope-copy tests passed.~%")
    t))
