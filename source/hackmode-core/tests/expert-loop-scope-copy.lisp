(in-package :hackmode-tests)

(defun run-expert-loop-scope-copy-tests ()
  (let* ((operation (copy-seq "op-a"))
         (run-id (copy-seq "run-1"))
         (state
           (hackmode:make-expert-loop-state
            :operation operation
            :run-id run-id
            :strategy :symbolic)))
    (setf (char operation 0) #\X
          (char run-id 0) #\X)
    (assert-equal "op-a"
                  (hackmode:expert-loop-state-operation state)
                  "loop state owns an operation-scope snapshot")
    (assert-equal "run-1"
                  (hackmode:expert-loop-state-run-id state)
                  "loop state owns a run-scope snapshot")
    (let ((exposed-operation (hackmode:expert-loop-state-operation state))
          (exposed-run-id (hackmode:expert-loop-state-run-id state)))
      (setf (char exposed-operation 0) #\Y
            (char exposed-run-id 0) #\Y)
      (assert-equal "op-a"
                    (hackmode:expert-loop-state-operation state)
                    "operation accessor does not expose mutable scope storage")
      (assert-equal "run-1"
                    (hackmode:expert-loop-state-run-id state)
                    "run accessor does not expose mutable scope storage"))
    (format t "Hackmode expert loop scope-copy tests passed.~%")
    t))
