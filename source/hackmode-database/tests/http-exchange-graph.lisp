(in-package :hackmode-database-tests)

(defun run-http-exchange-graph-tests ()
  (let* ((first (hackmode-database:make-http-exchange-record
                 :operation-id "op-http"
                 :capture-session-id "capture-1"
                 :exchange-id "exchange-1"
                 :method "GET"
                 :scheme "https"
                 :host "example.com"
                 :port 443
                 :path "/login?next=%2F"
                 :response-status 302
                 :request-body-digest "sha256:req"
                 :response-body-digest "sha256:resp"
                 :raw-evidence-ref "capture-1:120-418"
                 :observed-at "2026-08-30T18:55:00Z"
                 :duration-ms 17
                 :provenance '(:parser "ipx-http/1")))
         (same (hackmode-database:make-http-exchange-record
                :operation-id "op-http"
                :capture-session-id "capture-1"
                :exchange-id "exchange-1"
                :method "GET"
                :scheme "https"
                :host "example.com"
                :port 443
                :path "/login?next=%2F"
                :response-status 302
                :request-body-digest "sha256:req"
                :response-body-digest "sha256:resp"
                :raw-evidence-ref "capture-1:120-418"
                :observed-at "2026-08-30T18:55:00Z"
                :duration-ms 17
                :provenance '(:parser "ipx-http/1"))))
    (ensure (eq :http-exchange (hackmode-database:execution-record-kind first))
            "HTTP exchange has wrong execution kind")
    (ensure (string= (hackmode-database:execution-record-record-id first)
                     (hackmode-database:execution-record-record-id same))
            "replaying the same HTTP exchange changed stable identity")
    (ensure (string= "capture-1" (hackmode-database:execution-record-run-id first))
            "capture session identity was not retained")
    (ensure (string= "exchange-1" (hackmode-database:execution-record-call-id first))
            "exchange correlation identity was not retained")
    (let* ((path (merge-pathnames
                  (format nil "hackmode-http-exchange-~D/" (random 1000000000))
                  (uiop:temporary-directory)))
           (database (tek9:new-database "hackmode-http-exchange-test" :path path)))
      (unwind-protect
           (progn
             (tek9:open-database database)
             (hackmode-database:persist-execution-record database first)
             (hackmode-database:persist-execution-record database same)
             (let ((records
                     (hackmode-database:fetch-operation-execution-records
                      database "op-http" :kind :http-exchange)))
               (ensure (= 1 (length records))
                       "HTTP exchange replay duplicated canonical graph evidence")
               (ensure (equal (hackmode-database:execution-record-payload first)
                              (hackmode-database:execution-record-payload
                               (first records)))
                       "HTTP exchange metadata changed during Tek9 round-trip")))
        (when (tek9:db-is-open-p database)
          (tek9:close-database database))
        (when (probe-file path)
          (uiop:delete-directory-tree path :validate t))))
    (handler-case
        (progn
          (hackmode-database:make-http-exchange-record
           :operation-id "op-http"
           :capture-session-id "capture-1"
           :exchange-id "bad-port"
           :method "GET"
           :scheme "https"
           :host "example.com"
           :port 70000
           :path "/"
           :response-status 200
           :raw-evidence-ref "capture-1:0-10"
           :observed-at "2026-08-30T18:55:00Z"
           :duration-ms 1
           :provenance '(:parser "ipx-http/1"))
          (error "invalid HTTP port unexpectedly accepted"))
      (hackmode-database:execution-graph-validation-error () t)))
  t)
