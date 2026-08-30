(in-package :hackmode-tests)

(defun run-expert-state-snapshot-tests ()
  (let* ((call (hack-db:make-tool-call-record
                :operation-id "op-1" :run-id "run-1" :call-id "call-1"
                :capability-id "http-probe" :input '(:url "https://example.test")
                :provenance '(:source "fixture")))
         (result (hack-db:make-tool-result-record
                  :operation-id "op-1" :run-id "run-1" :call-id "call-1"
                  :result-id "result-1" :status :succeeded
                  :output '(:status 200) :provenance '(:source "fixture")))
         (assertion (hack-db:make-operational-kb-assertion
                     :assertion-id "a-1" :operation-id "op-1" :run-id "run-1"
                     :expert-id "recon" :expert-version "1"
                     :key "http.status" :value 200
                     :evidence-ids (list (hack-db:execution-record-record-id result))
                     :provenance '(:rule "fixture")))
         (snapshot (hackmode:expert-snapshot
                    :operation nil :assets nil :providers nil
                    :execution-records (list result call)
                    :operational-kb-entries (list assertion))))
    (assert (search "execution_record(" snapshot))
    (assert (search "\"tool-call\"" snapshot))
    (assert (search "\"tool-result\"" snapshot))
    (assert (search "\"http-probe\"" snapshot))
    (assert (search "operational_kb_entry(" snapshot))
    (assert (search "\"http.status\"" snapshot))
    (let ((call-pos (search (hack-db:execution-record-record-id call) snapshot))
          (result-pos (search (hack-db:execution-record-record-id result) snapshot)))
      (assert call-pos)
      (assert result-pos)
      (assert (< call-pos result-pos) () "Execution facts must sort by stable record ID.")))
    t)
