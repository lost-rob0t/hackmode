(in-package :hackmode-database-tests)

(defun run-long-term-kb-tests ()
  (let* ((source
           (make-operational-kb-assertion
            :assertion-id "a-promote"
            :operation-id "op-1"
            :run-id "run-1"
            :expert-id "recon"
            :expert-version "1"
            :key '(:service-pattern "nginx")
            :value '(:stable t)
            :evidence-ids '("call-1" "result-1")
            :provenance '(:source "fixture")))
         (promotion
           (make-long-term-kb-promotion
            :promotion-id "p-1"
            :source-assertion source
            :promoted-by "operator-policy"
            :promoter-version "1"
            :evidence-ids '("review-1")
            :provenance '(:reason "validated reusable pattern")))
         (same
           (make-long-term-kb-promotion
            :promotion-id "p-1"
            :source-assertion source
            :promoted-by "operator-policy"
            :promoter-version "1"
            :evidence-ids '("review-1")
            :provenance '(:reason "validated reusable pattern"))))
    (ensure (string= (long-term-kb-promotion-record-id promotion)
                     (long-term-kb-promotion-record-id same))
            "replaying a promotion changed its identity")
    (ensure (string= "op-1"
                     (long-term-kb-promotion-source-operation-id promotion))
            "promotion lost source operation identity")
    (ensure (string= (operational-kb-entry-record-id source)
                     (long-term-kb-promotion-source-assertion-id promotion))
            "promotion lost exact source assertion identity")
    (ensure (equal '("call-1" "result-1")
                   (long-term-kb-promotion-source-evidence-ids promotion))
            "promotion lost source evidence")
    (ensure (equal '("review-1")
                   (long-term-kb-promotion-evidence-ids promotion))
            "promotion lost promotion evidence")
    (ensure (equal (operational-kb-entry-key source)
                   (long-term-kb-promotion-key promotion))
            "promotion key drifted from source assertion")
    (ensure (equal (operational-kb-entry-value source)
                   (long-term-kb-promotion-value promotion))
            "promotion value drifted from source assertion")
    (let ((node (long-term-kb-promotion->tek9-node promotion))
          (edge (long-term-kb-source-edge promotion)))
      (ensure (string= (long-term-kb-promotion-record-id promotion)
                       (tek9:node-id node))
              "long-term promotion Tek9 identity drifted")
      (ensure (string= (long-term-kb-promotion-record-id promotion)
                       (tek9:edge-source edge))
              "promotion source edge has wrong source")
      (ensure (string= (operational-kb-entry-record-id source)
                       (tek9:edge-target edge))
              "promotion source edge lost operational assertion identity"))
    (handler-case
        (progn
          (make-long-term-kb-promotion
           :promotion-id "p-bad"
           :source-assertion
           (make-operational-kb-retraction
            :retraction-id "r-1"
            :operation-id "op-1"
            :run-id "run-1"
            :expert-id "recon"
            :expert-version "1"
            :target-assertion-id (operational-kb-entry-record-id source)
            :evidence-ids '("result-2")
            :provenance '(:source "fixture"))
           :promoted-by "operator-policy"
           :promoter-version "1"
           :evidence-ids '("review-2")
           :provenance '(:reason "invalid"))
          (error "retraction unexpectedly promoted into long-term KB"))
      (long-term-kb-validation-error () t)))
  t)
