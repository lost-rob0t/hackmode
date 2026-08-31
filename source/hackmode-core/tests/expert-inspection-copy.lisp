(in-package :hackmode-tests)

(defun run-expert-inspection-copy-tests ()
  (let* ((operation (copy-seq "op-1"))
         (run-id (copy-seq "run-1"))
         (engine (hackmode:make-expert-engine :mode :active))
         (state (hackmode:make-expert-loop-state
                 :operation operation
                 :run-id run-id
                 :strategy :symbolic))
         (inspection (hackmode:expert-run-inspection engine state)))
    (setf (char operation 0) #\X)
    (assert-equal "op-1"
                  (hackmode:expert-run-inspection-operation inspection)
                  "run inspection snapshots source strings")
    (let ((returned (hackmode:expert-run-inspection-run-id inspection)))
      (setf (char returned 0) #\X)
      (assert-equal "run-1"
                    (hackmode:expert-run-inspection-run-id inspection)
                    "run inspection returns defensive string copies")))
  (let* ((action
           (hackmode:make-expert-active-action
            :id "dispatch-1"
            :kind :dispatch
            :operation "op-1"
            :run-id "run-1"
            :expert-id "recon"
            :expert-version "3"
            :evidence-ids (list (copy-seq "evidence-1"))
            :payload
            (hackmode:make-expert-dispatch-payload
             :capability "http-probe"
             :provider "curl"
             :input "redacted")))
         (inspection (hackmode:expert-action-inspection action)))
    (let ((evidence (hackmode:expert-action-inspection-evidence-ids inspection)))
      (setf (char (first evidence) 0) #\X)
      (assert-equal "evidence-1"
                    (first (hackmode:expert-action-inspection-evidence-ids inspection))
                    "action inspection copies evidence string leaves"))
    (let ((summary (hackmode:expert-action-inspection-summary inspection)))
      (setf (char (getf summary :capability) 0) #\X)
      (assert-equal "http-probe"
                    (getf (hackmode:expert-action-inspection-summary inspection)
                          :capability)
                    "action inspection copies summary string leaves")))
  t)
