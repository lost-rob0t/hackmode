(in-package :hackmode-tests)

(defun run-expert-state-projection-test ()
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
    (let* ((call-id (hack-db:execution-record-record-id call))
           (result-id (hack-db:execution-record-record-id result))
           (call-pos (search call-id snapshot))
           (result-pos (search result-id snapshot)))
      (assert call-pos)
      (assert result-pos)
      (assert (if (string< call-id result-id)
                  (< call-pos result-pos)
                  (> call-pos result-pos))
              ()
              "Execution facts must sort by stable record ID."))
    t))

(defun run-expert-http-exchange-projection-test ()
  (let* ((exchange
           (hack-db:make-http-exchange-record
            :operation-id "op-http"
            :capture-session-id "capture-1"
            :exchange-id "exchange-1"
            :method "GET"
            :scheme "https"
            :host "example.test"
            :port 443
            :path "/login?next=%2F"
            :response-status 302
            :request-body-digest "sha256:req"
            :response-body-digest "sha256:res"
            :raw-evidence-ref "/private/captures/session.har#42"
            :observed-at "2026-08-30T19:00:00Z"
            :duration-ms 37
            :provenance '(:source :capture-fixture)))
         (snapshot
           (hackmode:expert-snapshot
            :operation nil :assets nil :providers nil
            :execution-records (list exchange)
            :operational-kb-entries nil)))
    (assert (search "http_exchange(" snapshot)
            ()
            "HTTP evidence must have a typed passive snapshot fact.")
    (dolist (expected '("\"op-http\""
                        "\"capture-1\""
                        "\"exchange-1\""
                        "\"GET\""
                        "\"https\""
                        "\"example.test\""
                        "443"
                        "\"/login?next=%2F\""
                        "302"
                        "\"sha256:req\""
                        "\"sha256:res\""
                        "\"2026-08-30T19:00:00Z\""
                        "37"))
      (assert (search expected snapshot)
              ()
              "Typed HTTP exchange fact is missing ~S." expected))
    (assert (not (search "/private/captures/session.har#42" snapshot))
            ()
            "Raw evidence references must not be copied into Prolog snapshots.")
    (assert (not (search "execution_record(" snapshot))
            ()
            "HTTP exchanges must use their bounded typed projection instead of the generic payload fact.")
    t))

(defun run-expert-persisted-snapshot-refresh-test ()
  (let* ((path (merge-pathnames
                (format nil "hackmode-expert-refresh-~D/" (random 1000000000))
                (uiop:temporary-directory)))
         (database (tek9:new-database "hackmode-expert-refresh" :path path))
         (operation (make-instance 'hackmode:operation
                                   :name "op-refresh"
                                   :dir "/tmp/op-refresh/")))
    (unwind-protect
         (progn
           (tek9:open-database database)
           (let* ((call (hack-db:make-tool-call-record
                         :operation-id "op-refresh"
                         :run-id "run-1"
                         :call-id "call-1"
                         :capability-id "http-probe"
                         :input '(:url "https://example.test")
                         :provenance '(:source "fixture")))
                  (result (hack-db:make-tool-result-record
                           :operation-id "op-refresh"
                           :run-id "run-1"
                           :call-id "call-1"
                           :result-id "result-1"
                           :status :succeeded
                           :output '(:status 200)
                           :provenance '(:source "fixture")))
                  (assertion (hack-db:make-operational-kb-assertion
                              :assertion-id "status-1"
                              :operation-id "op-refresh"
                              :run-id "run-1"
                              :expert-id "recon"
                              :expert-version "1"
                              :key "http.status"
                              :value 200
                              :evidence-ids
                              (list (hack-db:execution-record-record-id result))
                              :provenance '(:source "fixture"))))
             (hack-db:persist-tool-execution database call result)
             (hack-db:persist-operational-kb-entry database assertion)
             (let ((snapshot
                     (hackmode:expert-operation-snapshot
                      :database database
                      :operation operation
                      :run-id "run-1"
                      :assets nil
                      :providers nil)))
               (assert (search (hack-db:execution-record-record-id call) snapshot))
               (assert (search (hack-db:execution-record-record-id result) snapshot))
               (assert (search (hack-db:operational-kb-entry-record-id assertion)
                               snapshot)))
             (let ((next-assertion
                     (hack-db:make-operational-kb-assertion
                      :assertion-id "next-step"
                      :operation-id "op-refresh"
                      :run-id "run-1"
                      :expert-id "recon"
                      :expert-version "1"
                      :key "recon.next"
                      :value "subdomain-enumerate"
                      :evidence-ids (list (hack-db:execution-record-record-id result))
                      :provenance '(:source "fixture"))))
               (hack-db:persist-operational-kb-entry database next-assertion)
               (let ((refreshed
                       (hackmode:expert-operation-snapshot
                        :database database
                        :operation operation
                        :run-id "run-1"
                        :assets nil
                        :providers nil)))
                 (assert (search (hack-db:operational-kb-entry-record-id next-assertion)
                                 refreshed)
                         ()
                         "Fresh expert iteration must observe newly persisted KB evidence.")))))
      (when (tek9:db-is-open-p database)
        (tek9:close-database database))
      (when (probe-file path)
        (uiop:delete-directory-tree path :validate t))))
  t)

(defun run-expert-state-snapshot-tests ()
  (run-expert-state-projection-test)
  (run-expert-http-exchange-projection-test)
  (run-expert-persisted-snapshot-refresh-test)
  t)
