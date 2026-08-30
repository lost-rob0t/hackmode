(uiop:define-package :hackmode-database-execution-outcome-tests
  (:use :cl))

(in-package :hackmode-database-execution-outcome-tests)

(defun run-execution-outcome-kb-tests ()
  (let* ((call (hackmode-database:make-tool-call-record
                :operation-id "op-1" :run-id "run-1" :call-id "call-1"
                :capability-id "dns-resolve" :input "example.com"
                :provenance '(:provider "fixture")))
         (result (hackmode-database:make-tool-result-record
                  :operation-id "op-1" :run-id "run-1" :call-id "call-1"
                  :result-id "result-1" :status :failed :output "NXDOMAIN"
                  :provenance '(:provider "fixture")))
         (candidate
           (hackmode-database:make-execution-outcome-kb-candidate
            :call call :result result
            :expert-id "recon" :expert-version "1"
            :provenance '(:source :execution-evidence))))
    (assert (eq :assert (hackmode-database:operational-kb-entry-kind candidate)))
    (assert (string= "op-1" (hackmode-database:operational-kb-entry-operation-id candidate)))
    (assert (string= "run-1" (hackmode-database:operational-kb-entry-run-id candidate)))
    (assert (equal '(:execution-outcome "dns-resolve")
                   (hackmode-database:operational-kb-entry-key candidate)))
    (assert (equal '(:status :failed :call-id "call-1")
                   (hackmode-database:operational-kb-entry-value candidate)))
    (assert (equal (list (hackmode-database:execution-record-record-id call)
                         (hackmode-database:execution-record-record-id result))
                   (hackmode-database:operational-kb-entry-evidence-ids candidate)))
    (let ((again
            (hackmode-database:make-execution-outcome-kb-candidate
             :call call :result result
             :expert-id "recon" :expert-version "1"
             :provenance '(:source :execution-evidence))))
      (assert (string= (hackmode-database:operational-kb-entry-record-id candidate)
                       (hackmode-database:operational-kb-entry-record-id again))))
    (let ((bad-result
            (hackmode-database:make-tool-result-record
             :operation-id "op-2" :run-id "run-1" :call-id "call-1"
             :result-id "result-2" :status :succeeded :output t
             :provenance '(:provider "fixture")))
          (raised nil))
      (handler-case
          (hackmode-database:make-execution-outcome-kb-candidate
           :call call :result bad-result
           :expert-id "recon" :expert-version "1"
           :provenance '(:source :execution-evidence))
        (hackmode-database:execution-graph-validation-error ()
          (setf raised t)))
      (assert raised)))
  t)
