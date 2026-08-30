(uiop:define-package :hackmode-database-tests
  (:use :cl :hackmode-database)
  (:export #:run-tests))

(in-package :hackmode-database-tests)

(defun ensure (condition format-control &rest format-args)
  (unless condition
    (error (apply #'format nil format-control format-args))))

(defun run-tests ()
  (let* ((call (make-tool-call-record
                :operation-id "op-1"
                :run-id "run-1"
                :call-id "call-1"
                :capability-id "dns.resolve"
                :input '(:domain "example.com")
                :provenance '(:worker "database-test")))
         (result (make-tool-result-record
                  :operation-id "op-1"
                  :run-id "run-1"
                  :call-id "call-1"
                  :result-id "result-1"
                  :status :succeeded
                  :output '(:addresses ("192.0.2.1"))
                  :provenance '(:provider "fixture"))))
    (ensure (string= "op-1" (execution-record-operation-id call))
            "tool call lost operation identity")
    (ensure (string= "call-1" (execution-record-call-id call))
            "tool call lost call identity")
    (ensure (eq :tool-call (execution-record-kind call))
            "tool call has wrong kind")
    (ensure (eq :tool-result (execution-record-kind result))
            "tool result has wrong kind")
    (ensure (string= (execution-record-call-id call)
                     (execution-record-call-id result))
            "result is not linked to its call")
    (handler-case
        (progn
          (make-tool-result-record
           :operation-id "op-2"
           :run-id "run-1"
           :call-id "call-1"
           :result-id "result-2"
           :status :succeeded
           :output nil
           :provenance nil)
          (error "cross-operation result unexpectedly accepted"))
      (execution-graph-validation-error () t)))
  t)
