(in-package :hackmode-actors-tests)

(defvar *projected-documents* nil)

(defun parse-projected-json (json)
  (let ((document (jsown:parse json)))
    (push document *projected-documents*)
    document))

(defun envelope-data (envelope) envelope)

(defun run-envelope-shape-test ()
  (let* ((data (hackmode-actors::%new-data-object (list "name" "example.com")))
         (envelope (hackmode-actors:make-starintel-envelope
                    "id-1" "custom-dataset" "domain" data
                    :date-added 100 :date-updated 200)))
    (dolist (key '("id" "dataset" "dtype" "schemaVersion" "createdAt" "updatedAt"))
      (assert (member key (jsown:keywords envelope) :test #'string=)))
    (dolist (key '("_id" "schema_version" "date_added" "date_updated" "version" "data"))
      (assert (not (member key (jsown:keywords envelope) :test #'string=))))
    (assert-equal "0.10.1" (jsown:val envelope "schemaVersion"))
    (assert-equal 100 (jsown:val envelope "createdAt"))
    (assert-equal 200 (jsown:val envelope "updatedAt"))
    (assert-equal "custom-dataset" (jsown:val envelope "dataset"))
    (push envelope *projected-documents*)
    (assert (signals-condition-p
             'error
             (lambda () (hackmode-actors:make-starintel-envelope
                         "x" "custom" "domain" (jsown:empty-object)))))
    (assert (signals-condition-p
             'error
             (lambda () (hackmode-actors:make-starintel-envelope
                         "x" "custom" "domain"
                         (hackmode-actors::%new-data-object
                          (list "name" "example.com" "id" "override"))))))))

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
                      (hackmode-actors:asset->starintel-json asset :dataset "actor-test")))
         (parsed (parse-projected-json json))
         (again (hackmode-actors:asset->starintel-json asset :dataset "actor-test")))
    (assert (string= json again) ()
            "projection must be deterministic for the same asset")
    (assert-equal "domain" (jsown:val parsed "dtype") "domain dtype")
    (assert-equal "actor-test" (jsown:val parsed "dataset") "dataset override")
    (assert-equal "example.com"
                  (jsown:val (envelope-data parsed) "name")
                  "normalized domain name")
    (let ((reference (first (jsown:val parsed "resolvedAddresses"))))
      (assert-equal "1.2.3.4"
                    (jsown:val (first (jsown:val parsed "dnsRecords")) "value")
                    "exact resolved IP retained alongside typed reference")
      (assert-equal "org.starintel/core@1/host" (jsown:val reference "schema"))
      (assert-equal (hackmode:asset-deterministic-id
                     (make-instance 'hackmode:host :ip "1.2.3.4"))
                    (jsown:val reference "id")))
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
         (parsed (parse-projected-json (hackmode-actors:asset->starintel-json host))))
    (assert-equal "host" (jsown:val parsed "dtype") "host dtype")
    (assert-equal "203.0.113.7" (jsown:val (envelope-data parsed) "ip")
                  "host ip"))
  (let* ((url (make-instance 'hackmode:url
                             :scheme "https" :host "web.example"
                             :path "/a" :query "b=1"))
         (parsed (parse-projected-json (hackmode-actors:asset->starintel-json url))))
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
         (parsed (parse-projected-json json))
         (data (envelope-data parsed)))
    (assert-equal "operation" (jsown:val parsed "dtype") "operation dtype")
    (assert-equal "hunt the target" (jsown:val data "mission") "mission")
    (assert-equal "active" (jsown:val data "status") "status")
    (assert (= 1 (length (jsown:val data "phases"))) ()
            "default single seed phase")
    (assert-equal "recon"
                  (jsown:val (first (jsown:val data "phases")) "phaseId")
                  "seed phase name")))

(defun run-research-node-projection-test ()
  (let* ((json (hackmode-actors:research-node->starintel-json
                "enumerate subdomains" "running"
                :operation "stalker"))
         (parsed (parse-projected-json json))
         (data (envelope-data parsed)))
    (assert-equal "research-node" (jsown:val parsed "dtype")
                  "research-node dtype")
    (assert-equal "enumerate subdomains" (jsown:val data "objective")
                  "objective")
    (assert-equal "running" (jsown:val data "status") "status")))

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
         (parsed (parse-projected-json json))
         (data (envelope-data parsed)))
    (assert-equal "http-transaction" (jsown:val parsed "dtype")
                  "http-transaction dtype")
    (assert-equal "tx-1" (jsown:val data "transactionId") "transaction id")
    (assert-equal 200 (jsown:val data "responseStatus") "response status")
    (assert-equal "Bearer hunter2"
                  (jsown:val (jsown:val data "requestHeaders")
                             "Authorization")
                  "authorization header preserved exactly")
    (assert-equal "session=deadbeef"
                  (jsown:val (jsown:val data "requestHeaders") "Cookie")
                  "cookie header preserved exactly")
    (assert-equal "a=1; Secure"
                  (jsown:val (jsown:val data "responseHeaders") "Set-Cookie")
                  "set-cookie header preserved exactly")
    (assert-equal "spaces  and  tabs"
                  (jsown:val (jsown:val data "requestHeaders") "X-Custom")
                  "header whitespace preserved exactly")))

(defun run-spool-object-projection-test ()
  (let* ((spool-object
           (jsown:parse
            "{\"exchange_id\":\"ex-9\",\"timestamp_start\":100.25,\"timestamp_end\":100.9,\"request\":{\"method\":\"POST\",\"scheme\":\"https\",\"host\":\"api.example\",\"port\":443,\"path\":\"/v1/login\",\"headers\":{\"Authorization\":\"Basic dXNlcjpwYXNz\"}},\"response\":{\"status_code\":401,\"headers\":{\"WWW-Authenticate\":\"Basic realm=\\\"x\\\"\"}}}"))
         (json (hackmode-actors:spool-object->starintel-transaction-json
                spool-object))
         (parsed (parse-projected-json json))
         (data (envelope-data parsed)))
    (assert-equal "http-transaction" (jsown:val parsed "dtype")
                  "spool projection dtype")
    (assert-equal "ex-9" (jsown:val data "transactionId") "spool exchange id")
    (assert-equal "POST" (jsown:val data "method") "spool method")
    (assert-equal 401 (jsown:val data "responseStatus") "spool status")
    (assert-equal "Basic dXNlcjpwYXNz"
                  (jsown:val (jsown:val data "requestHeaders")
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
         (parsed (parse-projected-json json))
         (data (envelope-data parsed)))
    (assert-equal "web-capture" (jsown:val parsed "dtype") "web-capture dtype")
    (assert-equal "https://target.example/login" (jsown:val data "url") "url")
    (assert-equal "file:///spool/shot-1.png"
                  (jsown:val data "screenshotUri") "screenshot uri")
    (assert-equal "sha256:abc" (jsown:val data "screenshotHash")
                  "screenshot hash")))

(defun check-canonical-projected-documents ()
  (let ((path (merge-pathnames (format nil "hackmode-projections-~a.json" (tek9:make-key-id))
                               (uiop:temporary-directory)))
        (script (asdf:system-relative-pathname :hackmode-actors
                                               "../../tools/check-starintel-projections.py")))
    (unwind-protect
         (progn
           (with-open-file (stream path :direction :output :if-exists :supersede)
             (write-string (jsown:to-json (coerce (reverse *projected-documents*) 'vector)) stream))
           (uiop:run-program (list "python3" (namestring script) (namestring path))
                             :output *standard-output* :error-output *error-output*))
      (when (probe-file path) (delete-file path)))))

(defun run-projection-tests ()
  (setf *projected-documents* nil)
  (run-envelope-shape-test)
  (run-domain-projection-test)
  (run-host-url-projection-test)
  (run-operation-projection-test)
  (run-research-node-projection-test)
  (run-http-transaction-lossless-test)
  (run-spool-object-projection-test)
  (run-visual-evidence-projection-test)
  (check-canonical-projected-documents))
