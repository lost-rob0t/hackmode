(in-package :hackmode-actors-tests)

(defun envelope-data (envelope)
  (jsown:val envelope "data"))

(defun run-envelope-shape-test ()
  (let* ((data (jsown:empty-object))
         (envelope (hackmode-actors:make-starintel-envelope
                    "id-1" "star-intel" "domain" data
                    :date-added 100 :date-updated 200)))
    (dolist (key '("_id" "dataset" "dtype" "schema_version" "version"
                   "date_added" "date_updated" "sources" "evidence" "data"))
      (assert (member key (jsown:keywords envelope) :test #'string=) ()
              "envelope missing required key ~a" key))
    (assert (null (jsown:val envelope "sources")) ()
            "sources defaults to an empty array")
    (assert-equal "0.10.1" (jsown:val envelope "schema_version")
                  "schema version")
    (assert-equal "domain" (jsown:val envelope "dtype") "dtype")
    (assert (string= "1970-01-01T00:01:40"
                     (subseq (jsown:val envelope "date_added") 0 19))
            ()
            "date_added from unix seconds: ~a"
            (jsown:val envelope "date_added"))))

(defun run-domain-projection-test ()
  (let* ((asset (make-instance 'hackmode:domain
                               :record "Example.COM."
                               :record-type "a"
                               :ips '("1.2.3.4")
                               :operation "op-alpha"
                               :tool "crt.sh"
                               :date-added 100
                               :date-updated 200
                               :tags '("dns" "ct")))
         (json (progn (hackmode:normalize-asset asset)
                      (hackmode-actors:asset->starintel-json asset)))
         (parsed (jsown:parse json))
         (again (hackmode-actors:asset->starintel-json asset)))
    (assert (string= json again) ()
            "projection must be deterministic for the same asset")
    (assert-equal "domain" (jsown:val parsed "dtype") "domain dtype")
    (assert-equal "example.com"
                  (jsown:val (envelope-data parsed) "domain")
                  "normalized domain name")
    (assert-equal '("1.2.3.4")
                  (jsown:val (envelope-data parsed) "resolved_addresses")
                  "resolved addresses")
    (assert-equal "op-alpha"
                  (jsown:val (jsown:val parsed "provenance") "operation")
                  "provenance operation")))

(defun run-host-url-projection-test ()
  ;; Unresolved host has no StarIntel identity and must not project.
  (let ((unresolved (make-instance 'hackmode:host :hostname "ghost.example")))
    (assert (null (hackmode-actors:asset->starintel-json unresolved))))
  (let* ((host (make-instance 'hackmode:host
                              :hostname "web.example"
                              :ip "203.0.113.7"))
         (parsed (jsown:parse (hackmode-actors:asset->starintel-json host))))
    (assert-equal "host" (jsown:val parsed "dtype") "host dtype")
    (assert-equal "203.0.113.7" (jsown:val (envelope-data parsed) "ip")
                  "host ip"))
  (let* ((url (make-instance 'hackmode:url
                             :scheme "https" :host "web.example"
                             :path "/a" :query "b=1"))
         (parsed (jsown:parse (hackmode-actors:asset->starintel-json url))))
    (assert-equal "url" (jsown:val parsed "dtype") "url dtype")
    (assert (search "web.example" (jsown:val (envelope-data parsed) "url"))
            ()
            "canonical url value")))

(defun run-operation-projection-test ()
  (let* ((operation (make-instance 'hackmode:operation
                                   :name "stalker"
                                   :dir "/tmp/stalker/"
                                   :description "hunt the target"))
         (json (hackmode-actors:operation->starintel-json operation))
         (parsed (jsown:parse json))
         (data (envelope-data parsed)))
    (assert-equal "operation" (jsown:val parsed "dtype") "operation dtype")
    (assert-equal "hunt the target" (jsown:val data "mission") "mission")
    (assert-equal "active" (jsown:val data "status") "status")
    (assert (= 1 (length (jsown:val data "phases"))) ()
            "default single seed phase")
    (assert-equal "recon"
                  (jsown:val (first (jsown:val data "phases")) "name")
                  "seed phase name")))

(defun run-research-node-projection-test ()
  (let* ((json (hackmode-actors:research-node->starintel-json
                "enumerate subdomains" "active"
                :operation "stalker"))
         (parsed (jsown:parse json))
         (data (envelope-data parsed)))
    (assert-equal "research-node" (jsown:val parsed "dtype")
                  "research-node dtype")
    (assert-equal "enumerate subdomains" (jsown:val data "objective")
                  "objective")
    (assert-equal "active" (jsown:val data "status") "status")))

(defun run-http-transaction-lossless-test ()
  ;; Exact observed headers must survive the projection verbatim.
  (let* ((request-headers '(("Authorization" . "Bearer hunter2")
                            ("Cookie" . "session=deadbeef")
                            ("X-Custom" . "spaces  and  tabs")))
         (response-headers '(("Set-Cookie" . "a=1; Secure")
                             ("Server" . "nginx/1.25.3")))
         (json (hackmode-actors:http-transaction->starintel-json
                "tx-1" "GET" "https://target.example/admin" 200
                :scheme "https" :host "target.example" :path "/admin"
                :request-headers request-headers
                :response-headers response-headers))
         (parsed (jsown:parse json))
         (data (envelope-data parsed)))
    (assert-equal "http-transaction" (jsown:val parsed "dtype")
                  "http-transaction dtype")
    (assert-equal "tx-1" (jsown:val data "transaction_id") "transaction id")
    (assert-equal 200 (jsown:val data "response_status") "response status")
    (assert-equal "Bearer hunter2"
                  (jsown:val (jsown:val data "request_headers")
                             "Authorization")
                  "authorization header preserved exactly")
    (assert-equal "session=deadbeef"
                  (jsown:val (jsown:val data "request_headers") "Cookie")
                  "cookie header preserved exactly")
    (assert-equal "a=1; Secure"
                  (jsown:val (jsown:val data "response_headers") "Set-Cookie")
                  "set-cookie header preserved exactly")
    (assert-equal "spaces  and  tabs"
                  (jsown:val (jsown:val data "request_headers") "X-Custom")
                  "header whitespace preserved exactly")))

(defun run-spool-object-projection-test ()
  (let* ((spool-object
           (jsown:parse
            "{\"exchange_id\":\"ex-9\",\"timestamp_start\":100.25,\"timestamp_end\":100.9,\"request\":{\"method\":\"POST\",\"scheme\":\"https\",\"host\":\"api.example\",\"port\":443,\"path\":\"/v1/login\",\"headers\":{\"Authorization\":\"Basic dXNlcjpwYXNz\"}},\"response\":{\"status_code\":401,\"headers\":{\"WWW-Authenticate\":\"Basic realm=\\\"x\\\"\"}}}"))
         (json (hackmode-actors:spool-object->starintel-transaction-json
                spool-object))
         (parsed (jsown:parse json))
         (data (envelope-data parsed)))
    (assert-equal "http-transaction" (jsown:val parsed "dtype")
                  "spool projection dtype")
    (assert-equal "ex-9" (jsown:val data "transaction_id") "spool exchange id")
    (assert-equal "POST" (jsown:val data "method") "spool method")
    (assert-equal 401 (jsown:val data "response_status") "spool status")
    (assert-equal "Basic dXNlcjpwYXNz"
                  (jsown:val (jsown:val data "request_headers")
                             "Authorization")
                  "raw spool auth header survives verbatim")))

(defun run-visual-evidence-projection-test ()
  (let* ((record (hackmode-database:make-visual-evidence-record
                  :operation-id "stalker"
                  :run-id "run-1"
                  :job-id "job-1"
                  :asset-id "asset-1"
                  :requested-url "https://target.example/login"
                  :final-url "https://target.example/login"
                  :screenshot-evidence-ref "file:///spool/shot-1.png"
                  :screenshot-digest "sha256:abc"
                  :captured-at "2026-09-20T00:00:00Z"
                  :duration-ms 250
                  :http-status 200
                  :provenance '(:producer "hackmode-actors-test")))
         (json (hackmode-actors:visual-evidence->starintel-json record))
         (parsed (jsown:parse json))
         (data (envelope-data parsed)))
    (assert-equal "web-capture" (jsown:val parsed "dtype") "web-capture dtype")
    (assert-equal "https://target.example/login" (jsown:val data "url") "url")
    (assert-equal "file:///spool/shot-1.png"
                  (jsown:val data "screenshot_uri") "screenshot uri")
    (assert-equal "sha256:abc" (jsown:val data "screenshot_hash")
                  "screenshot hash")))

(defun run-projection-tests ()
  (run-envelope-shape-test)
  (run-domain-projection-test)
  (run-host-url-projection-test)
  (run-operation-projection-test)
  (run-research-node-projection-test)
  (run-http-transaction-lossless-test)
  (run-spool-object-projection-test)
  (run-visual-evidence-projection-test))
