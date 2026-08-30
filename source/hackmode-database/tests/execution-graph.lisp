(uiop:define-package :hackmode-database-tests
  (:use :cl :hackmode-database)
  (:export #:run-tests))

(in-package :hackmode-database-tests)

(defun ensure (condition format-control &rest format-args)
  (unless condition
    (error (apply #'format nil format-control format-args))))

(defun run-execution-graph-tests ()
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
    (ensure (eq :tool-call (execution-record-kind call))
            "tool call has wrong kind")
    (ensure (eq :tool-result (execution-record-kind result))
            "tool result has wrong kind")
    (ensure (validate-tool-result-link call result)
            "valid call/result link rejected")
    (ensure (string= (execution-record-record-id call)
                     (tek9:node-id (execution-record->tek9-node call)))
            "Tek9 node identity drifted")
    (let ((edge (tool-result-link-edge call result)))
      (ensure (string= (execution-record-record-id call) (tek9:edge-source edge))
              "result edge source drifted")
      (ensure (string= (execution-record-record-id result) (tek9:edge-target edge))
              "result edge target drifted"))
    (handler-case
        (progn
          (validate-tool-result-link
           call
           (make-tool-result-record
            :operation-id "op-2"
            :run-id "run-1"
            :call-id "call-1"
            :result-id "result-2"
            :status :succeeded
            :output nil
            :provenance '(:provider "fixture")))
          (error "cross-operation result unexpectedly accepted"))
      (execution-graph-validation-error () t))
    (handler-case
        (progn
          (make-tool-call-record
           :operation-id ""
           :run-id "run-1"
           :call-id "call-2"
           :capability-id "dns.resolve"
           :input nil
           :provenance '(:worker "database-test"))
          (error "empty operation identity unexpectedly accepted"))
      (execution-graph-validation-error () t))))

(defun run-operational-kb-tests ()
  (let* ((assertion
           (make-operational-kb-assertion
            :assertion-id "a-1"
            :operation-id "op-1"
            :run-id "run-1"
            :expert-id "recon"
            :expert-version "1"
            :key '(:hypothesis "wildcard-dns")
            :value '(:confidence 80)
            :evidence-ids '("call-1" "result-1")
            :provenance '(:worker "database-test")))
         (same
           (make-operational-kb-assertion
            :assertion-id "a-1"
            :operation-id "op-1"
            :run-id "run-1"
            :expert-id "recon"
            :expert-version "1"
            :key '(:hypothesis "wildcard-dns")
            :value '(:confidence 80)
            :evidence-ids '("call-1" "result-1")
            :provenance '(:worker "database-test")))
         (retraction
           (make-operational-kb-retraction
            :retraction-id "r-1"
            :operation-id "op-1"
            :run-id "run-1"
            :expert-id "recon"
            :expert-version "1"
            :target-assertion-id (operational-kb-entry-record-id assertion)
            :evidence-ids '("result-2")
            :provenance '(:worker "database-test"))))
    (ensure (eq :assert (operational-kb-entry-kind assertion))
            "operational KB assertion has wrong kind")
    (ensure (equal (operational-kb-entry-record-id assertion)
                   (operational-kb-entry-record-id same))
            "replaying the same assertion did not preserve identity")
    (ensure (string= "op-1" (operational-kb-entry-operation-id assertion))
            "operational KB assertion lost operation identity")
    (ensure (equal '("call-1" "result-1")
                   (operational-kb-entry-evidence-ids assertion))
            "operational KB assertion lost evidence provenance")
    (ensure (eq :retract (operational-kb-entry-kind retraction))
            "operational KB retraction has wrong kind")
    (ensure (string= (operational-kb-entry-record-id assertion)
                     (operational-kb-entry-target-assertion-id retraction))
            "retraction did not target exact assertion identity")
    (let ((edge (operational-kb-retraction-edge retraction)))
      (ensure (string= (operational-kb-entry-record-id assertion)
                       (tek9:edge-source edge))
              "retraction edge source drifted")
      (ensure (string= (operational-kb-entry-record-id retraction)
                       (tek9:edge-target edge))
              "retraction edge target drifted"))
    (handler-case
        (progn
          (make-operational-kb-retraction
           :retraction-id "r-cross"
           :operation-id "op-2"
           :run-id "run-2"
           :expert-id "recon"
           :expert-version "1"
           :target-assertion-id (operational-kb-entry-record-id assertion)
           :evidence-ids '("result-x")
           :provenance '(:worker "database-test"))
          (error "cross-operation retraction unexpectedly accepted"))
      (operational-kb-validation-error () t))))

(defun run-tests ()
  (run-execution-graph-tests)
  (run-operational-kb-tests)
  t)
