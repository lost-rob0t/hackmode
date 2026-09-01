(in-package :hackmode-tests)

(defun write-ascii-file (pathname content &key append)
  (with-open-file (stream pathname
                          :direction :output
                          :if-does-not-exist :create
                          :if-exists (if append :append :supersede)
                          :external-format :utf-8)
    (write-string content stream)))

(defun run-ipx-replay-tests ()
  (let* ((root (fresh-test-path "hackmode-ipx-replay"))
         (spool (merge-pathnames "capture.ipx.jsonl" root))
         (db (tek9:new-database "ipx-replay" :path root))
         (valid-line
           (format nil
                   "~a~%"
                   "{\"schema\":\"hackmode-ipx-http\",\"version\":1,\"operation_id\":\"op-ipx\",\"capture_session_id\":\"cap-1\",\"spool_id\":\"spool-1\",\"exchange_id\":\"exchange-1\",\"timestamp_start\":1000.0,\"timestamp_end\":1000.125,\"request\":{\"method\":\"GET\",\"scheme\":\"https\",\"host\":\"example.test\",\"port\":443,\"path\":\"/api?x=1\",\"http_version\":\"HTTP/2\",\"headers_raw_b64\":[],\"body_raw_b64\":\"\"},\"response\":{\"status_code\":200,\"reason\":\"OK\",\"http_version\":\"HTTP/2\",\"headers_raw_b64\":[],\"body_raw_b64\":\"\"},\"connection\":{},\"provider\":{\"name\":\"mitmproxy\",\"addon_schema\":\"hackmode-ipx-http\",\"addon_version\":1}}")))
    (unwind-protect
         (progn
           (uiop:ensure-all-directories-exist (list root))
           (tek9:open-database db)
           (write-ascii-file spool valid-line)
           (let ((first
                   (hackmode:replay-ipx-http-spool
                    db spool
                    :operation-id "op-ipx"
                    :capture-session-id "cap-1"
                    :source-id "spool-1")))
             (assert-equal 1
                           (hackmode:ipx-replay-result-committed-count first)
                           "first replay committed count")
             (assert-equal 0
                           (hackmode:ipx-replay-result-quarantine-count first)
                           "first replay quarantine count")
             (assert (not (hackmode:ipx-replay-result-truncated-p first)) ()
                     "Complete frame must not be marked truncated."))
           (let ((exchanges
                   (hackmode-database:fetch-operation-execution-records
                    db "op-ipx" :run-id "cap-1" :kind :http-exchange)))
             (assert-equal 1 (length exchanges) "one canonical HTTP exchange")
             (let* ((exchange (first exchanges))
                    (payload (hackmode-database:execution-record-payload exchange)))
               (assert-equal "GET" (getf payload :method) "HTTP method")
               (assert-equal "https" (getf payload :scheme) "HTTP scheme")
               (assert-equal "example.test" (getf payload :host) "HTTP host")
               (assert-equal 443 (getf payload :port) "HTTP port")
               (assert-equal "/api?x=1" (getf payload :path) "HTTP path")
               (assert-equal 200 (getf payload :response-status) "HTTP status")
               (assert-equal 125 (getf payload :duration-ms) "HTTP duration")
               (assert (search "spool-1" (getf payload :raw-evidence-ref)) ()
                       "HTTP exchange must retain a raw spool evidence reference.")))
           (let ((again
                   (hackmode:replay-ipx-http-spool
                    db spool
                    :operation-id "op-ipx"
                    :capture-session-id "cap-1"
                    :source-id "spool-1")))
             (assert-equal 0
                           (hackmode:ipx-replay-result-committed-count again)
                           "checkpointed replay does not duplicate exchange")
             (assert-equal 1
                           (length
                            (hackmode-database:fetch-operation-execution-records
                             db "op-ipx" :run-id "cap-1" :kind :http-exchange))
                           "replay-safe exchange count"))

           (write-ascii-file spool (format nil "{not-json}~%") :append t)
           (let ((malformed
                   (hackmode:replay-ipx-http-spool
                    db spool
                    :operation-id "op-ipx"
                    :capture-session-id "cap-1"
                    :source-id "spool-1")))
             (assert-equal 1
                           (hackmode:ipx-replay-result-quarantine-count malformed)
                           "malformed complete frame quarantined")
             (assert-equal 1
                           (length
                            (hackmode-database:fetch-capture-quarantine-records
                             db "op-ipx" "cap-1" "spool-1"))
                           "one durable malformed-frame quarantine"))

           (let* ((checkpoint-before
                    (hackmode-database:fetch-latest-capture-checkpoint
                     db "op-ipx" "cap-1" "spool-1"))
                  (offset-before
                    (getf (hackmode-database:execution-record-payload checkpoint-before)
                          :offset)))
             (write-ascii-file spool "{" :append t)
             (let ((truncated
                     (hackmode:replay-ipx-http-spool
                      db spool
                      :operation-id "op-ipx"
                      :capture-session-id "cap-1"
                      :source-id "spool-1")))
               (assert (hackmode:ipx-replay-result-truncated-p truncated) ()
                       "Unterminated final frame must be classified as truncated.")
               (assert-equal 1
                             (hackmode:ipx-replay-result-quarantine-count truncated)
                             "truncated frame quarantined"))
             (let* ((checkpoint-after
                      (hackmode-database:fetch-latest-capture-checkpoint
                       db "op-ipx" "cap-1" "spool-1"))
                    (offset-after
                      (getf (hackmode-database:execution-record-payload checkpoint-after)
                            :offset)))
               (assert-equal offset-before offset-after
                             "truncated frame does not advance checkpoint"))))
      (when (tek9:db-is-open-p db)
        (tek9:close-database db))
      (remove-test-path root)))
  t)