(in-package :hackmode-database-tests)

(defun run-global-kb-tests ()
  (let* ((source
           (make-operational-kb-assertion
            :assertion-id "a-global"
            :operation-id "op-global"
            :run-id "run-global"
            :expert-id "recon"
            :expert-version "1"
            :key '(:service-pattern "nginx")
            :value '(:stable t)
            :evidence-ids '("call-global" "result-global")
            :provenance '(:source "fixture")))
         (promotion
           (make-long-term-kb-promotion
            :promotion-id "p-global"
            :source-assertion source
            :promoted-by "operator-policy"
            :promoter-version "1"
            :evidence-ids '("review-global")
            :provenance '(:reason "validated reusable pattern")))
         (export
           (make-global-kb-export
            :export-id "export-1"
            :source-promotion promotion
            :exported-by "operator"
            :exporter-version "1"
            :evidence-ids '("approval-global")
            :provenance '(:reason "explicit loot")))
         (same
           (make-global-kb-export
            :export-id "export-1"
            :source-promotion promotion
            :exported-by "operator"
            :exporter-version "1"
            :evidence-ids '("approval-global")
            :provenance '(:reason "explicit loot"))))
    (ensure (string= (global-kb-export-record-id export)
                     (global-kb-export-record-id same))
            "replaying global export changed its identity")
    (ensure (string= (long-term-kb-promotion-record-id promotion)
                     (global-kb-export-source-promotion-id export))
            "global export lost source promotion identity")
    (ensure (string= "op-global"
                     (global-kb-export-source-operation-id export))
            "global export lost source operation provenance")
    (ensure (equal (long-term-kb-promotion-key promotion)
                   (global-kb-export-key export))
            "global export key drifted from long-term promotion")
    (ensure (equal (long-term-kb-promotion-value promotion)
                   (global-kb-export-value export))
            "global export value drifted from long-term promotion")
    (ensure (equal '("approval-global")
                   (global-kb-export-evidence-ids export))
            "global export lost explicit export evidence")
    (let ((edge (global-kb-source-edge export)))
      (ensure (string= (global-kb-export-record-id export)
                       (tek9:edge-source edge))
              "global source edge has wrong source")
      (ensure (string= (long-term-kb-promotion-record-id promotion)
                       (tek9:edge-target edge))
              "global source edge lost exact long-term promotion"))
    (handler-case
        (progn
          (make-global-kb-export
           :export-id "export-no-evidence"
           :source-promotion promotion
           :exported-by "operator"
           :exporter-version "1"
           :evidence-ids nil
           :provenance '(:reason "invalid"))
          (error "global export unexpectedly accepted without evidence"))
      (global-kb-validation-error () t)))
  t)
