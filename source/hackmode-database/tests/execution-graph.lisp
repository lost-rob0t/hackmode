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
                :provenance '(:source "database-test")))
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
           :provenance '(:source "database-test"))
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
            :provenance '(:source "database-test")))
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
            :provenance '(:source "database-test")))
         (retraction
           (make-operational-kb-retraction
            :retraction-id "r-1"
            :operation-id "op-1"
            :run-id "run-1"
            :expert-id "recon"
            :expert-version "1"
            :target-assertion-id (operational-kb-entry-record-id assertion)
            :evidence-ids '("result-2")
            :provenance '(:source "database-test"))))
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
           :provenance '(:source "database-test"))
          (error "cross-operation retraction unexpectedly accepted"))
      (operational-kb-validation-error () t))))

(defun run-operation-snapshot-read-tests ()
  (let* ((path (merge-pathnames
                (format nil "hackmode-snapshot-~D/" (random 1000000000))
                (uiop:temporary-directory)))
         (database (tek9:new-database "hackmode-snapshot-test" :path path)))
    (unwind-protect
         (progn
           (tek9:open-database database)
           (let* ((call-a (make-tool-call-record
                           :operation-id "op-a" :run-id "run-1" :call-id "call-a"
                           :capability-id "dns.resolve" :input '(:domain "a.example")
                           :provenance '(:source "fixture")))
                  (result-a (make-tool-result-record
                             :operation-id "op-a" :run-id "run-1" :call-id "call-a"
                             :result-id "result-a" :status :succeeded
                             :output '(:addresses ("192.0.2.10"))
                             :provenance '(:source "fixture")))
                  (call-b (make-tool-call-record
                           :operation-id "op-a" :run-id "run-2" :call-id "call-b"
                           :capability-id "http.probe" :input '(:url "https://a.example")
                           :provenance '(:source "fixture")))
                  (foreign (make-tool-call-record
                            :operation-id "op-b" :run-id "run-1" :call-id "call-x"
                            :capability-id "dns.resolve" :input '(:domain "b.example")
                            :provenance '(:source "fixture")))
                  (assertion (make-operational-kb-assertion
                              :assertion-id "hyp-1" :operation-id "op-a"
                              :run-id "run-1" :expert-id "recon" :expert-version "1"
                              :key '(:hypothesis "wildcard-dns") :value '(:confidence 80)
                              :evidence-ids (list (execution-record-record-id result-a))
                              :provenance '(:source "fixture")))
                  (retraction (make-operational-kb-retraction
                               :retraction-id "hyp-1-retracted" :operation-id "op-a"
                               :run-id "run-2" :expert-id "recon" :expert-version "1"
                               :target-assertion-id (operational-kb-entry-record-id assertion)
                               :evidence-ids (list (execution-record-record-id call-b))
                               :provenance '(:source "fixture"))))
             (persist-tool-execution database call-a result-a)
             (persist-execution-record database call-b)
             (persist-execution-record database foreign)
             (persist-operational-kb-entry database assertion)
             (persist-operational-kb-entry database retraction)
             (let ((records (fetch-operation-execution-records database "op-a"))
                   (run-1 (fetch-operation-execution-records database "op-a" :run-id "run-1"))
                   (kb (fetch-operational-kb-entries database "op-a")))
               (ensure (= 3 (length records))
                       "operation execution snapshot did not return all typed records")
               (ensure (every (lambda (record)
                                (string= "op-a" (execution-record-operation-id record)))
                              records)
                       "operation execution snapshot leaked another operation")
               (ensure (= 2 (length run-1))
                       "run filter did not return call/result pair")
               (ensure (= 2 (length kb))
                       "operational KB snapshot did not include assertion and retraction")
               (ensure (every (lambda (entry)
                                (string= "op-a" (operational-kb-entry-operation-id entry)))
                              kb)
                       "operational KB snapshot leaked another operation")
               (ensure (find :assert kb :key #'operational-kb-entry-kind)
                       "operational KB snapshot lost assertion")
               (ensure (find :retract kb :key #'operational-kb-entry-kind)
                       "operational KB snapshot lost retraction"))))
      (when (tek9:db-is-open-p database)
        (tek9:close-database database))
      (when (probe-file path)
        (uiop:delete-directory-tree path :validate t))))
  t)

(defun run-tests ()
  (run-execution-graph-tests)
  (run-operational-kb-tests)
  (run-operation-snapshot-read-tests)
  t)
