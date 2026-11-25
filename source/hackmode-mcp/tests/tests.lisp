(defpackage :hackmode-mcp-tests
  (:use :cl)
  (:export :run-tests))

(in-package :hackmode-mcp-tests)

(defun assert-equal (expected actual &optional (label "values"))
  (assert (equal expected actual) ()
          "Expected ~a to be ~s, got ~s" label expected actual))

(defun assert-true (value &optional (label "value"))
  (assert (not (null value)) () "Expected ~a to be non-nil" label))

(defun fresh-test-path ()
  (merge-pathnames
   (format nil "hackmode-mcp-~a/" (tek9:make-key-id))
   (uiop:temporary-directory)))

(defun remove-test-path (path)
  (ignore-errors
   (uiop:delete-directory-tree path :validate t :if-does-not-exist :ignore)))

(defun jsval (object key)
  (and (consp object) (jsown:val-safe object key)))

(defun request (id method &optional params)
  (cons :obj
        (append (list (cons "jsonrpc" "2.0")
                      (cons "id" id)
                      (cons "method" method))
                (when params (list (cons "params" params))))))

(defun notification (method)
  (list :obj (cons "jsonrpc" "2.0") (cons "method" method)))

(defun call-tool-request (id name &optional arguments)
  (request id "tools/call"
           (cons :obj
                 (append (list (cons "name" name))
                         (when arguments (list (cons "arguments" arguments)))))))

(defun tool-error-message (response)
  "The error text carried by an isError tool result."
  (let ((result (jsval response "result")))
    (let ((content (jsval result "content")))
      (jsval (first content) "text"))))

;;;; Schema derivation.

(defun run-schema-derivation-test ()
  (let ((schema (hackmode-mcp:message-input-schema "run-recon-tool"))
        (recon (hackmode-starlang:declared-recon-tools)))
    (assert-equal "object" (jsval schema "type") "input schema type")
    (let ((properties (jsval schema "properties")))
      (let ((run-id (jsval properties "runId")))
        (assert-equal "string" (jsval run-id "type") "runId type")
        (assert-equal (getf (hackmode-mcp::pentest-declaration :scalar "run-id")
                            :pattern)
                      (jsval run-id "pattern")
                      "runId declared pattern"))
      (let ((tool (jsval properties "tool")))
        (assert-equal "string" (jsval tool "type") "tool type")
        (assert-equal recon (jsval tool "enum") "tool enum from the graph"))
      (assert-equal "string" (jsval (jsval properties "target") "type")
                    "target type")
      (assert-equal "object" (jsval (jsval properties "options") "type")
                    "options map type"))
    (assert-equal '("tool" "target") (jsval schema "required")
                  "runId optional at the MCP boundary, wire-required fields kept"))
  ;; List types derive array schemas (recon-tool-completed.argv).
  (let ((schema (hackmode-mcp:message-input-schema "recon-tool-completed"
                                                   :optional-required '())))
    (assert-equal '("runId" "tool" "target" "argv" "exitCode" "stdout" "stderr")
                  (jsval schema "required")
                  "message required list when nothing is optionalized")
    (let ((argv (jsval (jsval (jsval schema "properties") "argv") "items")))
      (assert-equal "string" (jsval argv "type") "argv item type")))
  ;; Per-tool schemas: the message schema minus the tool selector - the
  ;; MCP tool IS the declared tool.
  (dolist (tool (hackmode-starlang:declared-tools))
    (let ((definition (hackmode-mcp:find-tool tool)))
      (assert-true definition "declared tool has an MCP tool")
      (let ((schema (hackmode-mcp:mcp-tool-input-schema definition)))
        (assert-equal "object" (jsval schema "type") "per-tool schema type")
        (assert-true (null (jsval (jsval schema "properties") "tool"))
                     "per-tool schema has no tool selector")
        (assert-equal '("target") (jsval schema "required")
                      "per-tool schema requires only target")))))

;;;; Catalog.

(defun run-catalog-test ()
  (let ((names (mapcar #'hackmode-mcp:mcp-tool-name
                       (hackmode-mcp:tool-definitions))))
    ;; One MCP tool per declared pentest tool, named verbatim, plus the
    ;; fixed operation surface.
    (assert-equal
     (append '("op_list" "op_create" "op_use" "op_status"
               "asset_query" "capability_list")
             (hackmode-starlang:declared-tools))
     names
     "derived catalog")
    ;; Every declared tool's MCP identity is the declared name.
    (dolist (tool (hackmode-starlang:declared-tools))
      (assert-true (hackmode-mcp:find-tool tool)
                   "declared tool individually callable")))
  (let ((table (mapcar #'first hackmode-mcp:*declared-tool-backends*)))
    (assert-equal (sort (copy-list (hackmode-starlang:declared-tools)) #'string<)
                  (sort (copy-list table) #'string<)
                  "dispatch table covers the declared catalog exactly"))
  ;; Registered backends resolve through the live provider registry.
  (assert (eq :registered
              (getf (hackmode-mcp:tool-backend-status "nuclei") :status))
          () "nuclei backend registered by hackmode-starlang load")
  (assert (eq :registered
              (getf (hackmode-mcp:tool-backend-status "subfinder") :status))
          () "subfinder backend registered by hackmode-provider-recon load")
  (assert (eq :registered
              (getf (hackmode-mcp:tool-backend-status "crtsh") :status))
          () "crtsh backend registered")
  (assert (eq :registered
              (getf (hackmode-mcp:tool-backend-status "massdns") :status))
          () "massdns backend registered by hackmode-provider-dns load")
  ;; Declared-but-pending tools report pending, never undeclared.
  (dolist (tool '("nmap" "httpx" "katana"))
    (let ((status (hackmode-mcp:tool-backend-status tool)))
      (assert (eq :pending (getf status :status))
              ()
              "~a is declared and pending" tool)
      (assert-true (getf status :detail) "pending detail")))
  ;; The zap daemon backends (hackmode-provider-zap) are optional systems:
  ;; registered when loaded, pending with a load instruction otherwise.
  (let ((zap-loaded (and (find-package :hackmode-provider-zap)
                         (fboundp (find-symbol "REGISTER-ZAP-PROVIDERS"
                                               :hackmode-provider-zap)))))
    (dolist (tool '("zap" "zap-race-probe" "zap-smuggle-probe"
                    "zap-jwt-toolkit" "zap-param-miner" "zap-authz-diff"
                    "zap-content-discovery" "zap-graphql-probe"))
      (let ((status (hackmode-mcp:tool-backend-status tool)))
        (if zap-loaded
            (progn
              (assert (eq :registered (getf status :status))
                      ()
                      "~a registered when the zap provider system is loaded"
                      tool)
              (assert (getf status :capability) ()
                      "zap backend capability"))
            (progn
              (assert (eq :pending (getf status :status))
                      ()
                      "~a is declared and pending" tool)
              (assert-true (getf status :detail) "pending detail"))))))
  (assert (eq :undeclared
              (getf (hackmode-mcp:tool-backend-status "not-a-tool") :status))
          () "undeclared tool status"))

;;;; Protocol handling.

(defun run-protocol-test ()
  ;; initialize echoes a supported version, answers its latest otherwise.
  (let ((response (hackmode-mcp:handle-message
                   (request 1 "initialize"
                            (list :obj (cons "protocolVersion" "2024-11-05"))))))
    (assert-equal "2024-11-05"
                  (jsval (jsval response "result") "protocolVersion")
                  "supported version echoed"))
  (let ((response (hackmode-mcp:handle-message
                   (request 2 "initialize"
                            (list :obj (cons "protocolVersion" "1999-01-01"))))))
    (assert-equal hackmode-mcp:*latest-protocol-version*
                  (jsval (jsval response "result") "protocolVersion")
                  "unsupported version answered with the server's latest"))
  (let ((result (jsval (hackmode-mcp:handle-message
                        (request 3 "initialize")) "result")))
    (assert-true (jsval (jsval result "capabilities") "tools")
                 "tools capability declared")
    (assert-equal "hackmode-mcp"
                  (jsval (jsval result "serverInfo") "name")
                  "server info name"))
  ;; Notifications are never answered.
  (assert (null (hackmode-mcp:handle-message
                 (notification "notifications/initialized")))
          () "initialized notification silent")
  ;; tools/list exposes the derived catalog with input schemas.
  (let* ((response (hackmode-mcp:handle-message (request 4 "tools/list")))
         (tools (jsval (jsval response "result") "tools")))
    (assert-equal 21 (length tools) "catalog size over the wire")
    (let ((first (first tools)))
      (assert-true (jsval first "name") "tool name")
      (assert-true (jsval first "description") "tool description")
      (assert-true (jsval first "inputSchema") "tool inputSchema")))
  ;; Unknown tool is a protocol error; unknown method is -32601.
  (let ((response (hackmode-mcp:handle-message
                   (call-tool-request 5 "not_a_tool"))))
    (assert-equal -32602 (jsval (jsval response "error") "code")
                  "unknown tool protocol error"))
  (let ((response (hackmode-mcp:handle-message (request 6 "no/such"))))
    (assert-equal -32601 (jsval (jsval response "error") "code")
                  "unknown method protocol error"))
  ;; A condition inside a handler is a tool execution error (isError).
  (let* ((response (hackmode-mcp:handle-message
                    (call-tool-request 7 "op_use" (list :obj))))
         (result (jsval response "result")))
    (assert-equal :true (jsval result "isError")
                  "missing argument surfaces as a tool execution error")
    (assert-true (jsval result "structuredContent")
                 "error result still carries structured content"))
  ;; ping.
  (let ((response (hackmode-mcp:handle-message (request 8 "ping"))))
    (assert-equal '(:obj) (jsval response "result") "ping result"))
  ;; The stdio line layer: undecodable input answers -32700, valid JSON
  ;; that is not an object answers -32600, notifications write nothing.
  (let ((output (make-string-output-stream)))
    (hackmode-mcp:handle-line "not json {" output)
    (let ((response (jsown:parse (get-output-stream-string output))))
      (assert-equal -32700 (jsval (jsval response "error") "code")
                    "parse error protocol code")))
  (let ((output (make-string-output-stream)))
    (hackmode-mcp:handle-line "[1,2]" output)
    (let ((response (jsown:parse (get-output-stream-string output))))
      (assert-equal -32600 (jsval (jsval response "error") "code")
                    "non-object request protocol code")))
  (let ((output (make-string-output-stream)))
    (hackmode-mcp:handle-line
     (jsown:to-json (notification "notifications/initialized")) output)
    (assert-equal "" (get-output-stream-string output)
                  "notification produces no stdout frame"))
  (let ((output (make-string-output-stream)))
    (hackmode-mcp:handle-line "   " output)
    (assert-equal "" (get-output-stream-string output)
                  "blank line produces no frame")))

;;;; Operation tools over a real temp registry + store.

(defun close-quietly (database)
  (ignore-errors
   (when (tek9:db-is-open-p database)
     (tek9:close-database database))))

(defun run-operation-tools-test ()
  (let* ((root (fresh-test-path))
         (original-cwd (uiop:getcwd))
         (original-operations-dir (uiop:getenv "HACKMODE_OPERATIONS_DIR"))
         (registry (tek9:new-database
                    "operations" :path (merge-pathnames "ops/" root))))
    (unwind-protect
         (let ((hackmode:*operations-database* registry)
               (hackmode:*db* nil)
               (hackmode:*current-operation* nil))
           ;; Redirect the default operations root into the temp tree:
           ;; the operator's real ~/hackmode is never touched by tests.
           (setf (uiop:getenv "HACKMODE_OPERATIONS_DIR") (namestring root))
           (let ((created (hackmode-mcp:call-tool
                           "op_create"
                           (list :obj
                                 (cons "name" "test-op")
                                 (cons "description" "mcp test operation")))))
             (assert-equal "test-op"
                           (jsval (jsval created "operation") "name")
                           "created operation name")
             (assert-equal "mcp test operation"
                           (jsval (jsval created "operation") "description")
                           "created operation description")
             (assert-true
              (uiop:directory-exists-p (merge-pathnames "test-op/" root))
              "operation workspace created under the configured root"))
           (let ((listing (hackmode-mcp:call-tool "op_list" (list :obj))))
             (assert-true
              (find "test-op" (jsval listing "operations")
                    :key (lambda (operation) (jsval operation "name"))
                    :test #'string=)
              "op_list sees the new operation")
             (assert-equal :null (jsval listing "current")
                           "nothing selected yet"))
           ;; Asset queries fail closed before an operation is open.
           (let* ((response (hackmode-mcp:handle-message
                             (call-tool-request 10 "asset_query")))
                  (result (jsval response "result")))
             (assert-equal :true (jsval result "isError")
                           "asset_query fails closed with no open store"))
           (let ((used (hackmode-mcp:call-tool
                        "op_use" (list :obj (cons "name" "test-op")))))
             (assert-equal :true
                           (jsval (jsval used "operation") "active")
                           "selected operation active")
             (assert-true hackmode:*db* "operation store opened")
             (assert-true (tek9:db-is-open-p hackmode:*db*)
                          "operation store is open"))
           (let ((status (hackmode-mcp:call-tool "op_status" (list :obj))))
             (assert-equal "test-op"
                           (jsval (jsval status "operation") "name")
                           "op_status reports the selection"))
           (hackmode:store-asset
            (make-instance 'hackmode:domain
                           :record "Example.COM" :record-type "A"))
           (let ((assets (hackmode-mcp:call-tool
                          "asset_query"
                          (list :obj (cons "type" "domain")))))
             (assert-equal 1 (jsval assets "count") "asset_query count")
             (assert-equal 1 (jsval assets "total") "asset_query total")
             (assert-equal :false (jsval assets "truncated")
                           "no silent truncation")
             (let ((asset (first (jsval assets "assets"))))
               (assert-equal "example.com|A" (jsval asset "value")
                             "canonical asset value (name|type)")
               (assert-equal "example.com" (jsval asset "name")
                             "domain name field")
               (assert-equal "domain" (jsval asset "kind") "asset kind")))
           (let ((empty (hackmode-mcp:call-tool
                         "asset_query"
                         (list :obj (cons "type" "finding")))))
             (assert-equal 0 (jsval empty "count")
                           "typed query over another kind"))
           (let ((capped (hackmode-mcp:call-tool
                          "asset_query"
                          (list :obj
                                (cons "type" "domain")
                                (cons "limit" 1)))))
             (assert-equal 1 (jsval capped "count") "explicit limit honored")
             (assert-equal :false (jsval capped "truncated")
                           "limit equal to total is not truncation")))
      (progn
        ;; SBCL's (setf getenv) rejects NIL; an empty value reads back as
        ;; unset for default-operations-root.
        (setf (uiop:getenv "HACKMODE_OPERATIONS_DIR")
              (or original-operations-dir ""))
        (uiop:chdir original-cwd)
        (close-quietly hackmode:*db*)
        (close-quietly registry)
        (remove-test-path root)))))

;;;; Run tools with injected runners.

(defparameter *sample-nuclei-line*
  "{\"template-id\":\"http/misconfig/generic\",\"info\":{\"severity\":\"high\"},\"host\":\"scan.example.com\"}")

(defun register-fake-nuclei (behavior)
  (hackmode:register-capability-provider
   :vuln-scan :nuclei
   (lambda (target)
     (hackmode:normalize-asset target)
     (ecase behavior
       (:success
        (list (make-instance 'hackmode:finding
                             :document-id (hackmode:asset-deterministic-id target)
                             :finding-type "nuclei-finding"
                             :data *sample-nuclei-line*
                             :tool "nuclei"
                             :tags '("vuln" "nuclei"))))
       (:failure
        (error "Nuclei exited with status 2.~%stderr: [ERR] partial failure~%stdout: ~a"
               *sample-nuclei-line*))))
   :input-type 'hackmode:domain
   :output-types '(hackmode:finding)
   :priority 20))

(defun run-run-tool-test ()
  (let ((root (fresh-test-path)))
    (unwind-protect
         (let ((hackmode:*db* (tek9:new-database "operation" :path root))
               (hackmode:*asset-event-hook*
                 (make-instance 'nhooks:hook-any :handlers nil)))
           (tek9:open-database hackmode:*db*)
           (hackmode:clear-capability-providers)
           (register-fake-nuclei :success)
           ;; Success path: job outcome, lossless evidence, outbox entry.
           (let* ((response (hackmode-mcp:handle-message
                             (call-tool-request
                              20 "nuclei"
                              (list :obj
                                    (cons "target" "example.com")
                                    (cons "runId" "run-abc-1")))))
                  (result (jsval response "result"))
                  (content (jsval result "structuredContent")))
             (assert-equal :false (jsval result "isError")
                           "successful run is not an error")
             (let ((job (jsval content "job")))
               (assert-equal "succeeded" (jsval job "state")
                             "job state over the wire")
               (assert-equal 1 (jsval job "createdCount")
                             "persisted finding count"))
             (let* ((assets (jsval (jsval content "job") "assets"))
                    (asset (first assets)))
               (assert-equal *sample-nuclei-line* (jsval asset "data")
                             "exact finding evidence survives the surface"))
             (let ((tool-run (jsval content "toolRun")))
               (assert-equal "run-abc-1" (jsval tool-run "runId")
                             "caller runId honored")
               (assert-equal "completed" (jsval tool-run "status")
                             "completed status")
               (assert-true (jsval tool-run "_id")
                            "canonical _id present (outbox contract)")
               (assert-equal "org.hackmode/pentest@1/tool-run"
                             (jsval tool-run "dtype")
                             "dtype present (outbox contract)")
               (assert-equal "hackmode" (jsval tool-run "dataset")
                             "dataset present")
               (assert-equal "vuln-scan"
                             (jsval (jsval tool-run "raw") "capability")
                             "raw map records the capability"))
             (assert-equal 1
                           (length (hackmode:list-outbox-entries hackmode:*db*))
                           "tool-run document enqueued once"))
           ;; Failure path: isError, complete error text, failed doc still
           ;; enqueued.
           (register-fake-nuclei :failure)
           (let* ((response (hackmode-mcp:handle-message
                             (call-tool-request
                              21 "nuclei"
                              (list :obj
                                    (cons "target" "example.com")))))
                  (result (jsval response "result"))
                  (content (jsval result "structuredContent")))
             (assert-equal :true (jsval result "isError")
                           "failed job is a tool execution error")
             (assert (search "partial failure"
                             (jsval (jsval content "job") "error"))
                     ()
                     "job error text present")
             (let ((tool-run (jsval content "toolRun")))
               (assert-equal "failed" (jsval tool-run "status")
                             "failed tool-run status")
               (assert (search "partial failure"
                               (jsval (jsval tool-run "raw") "error"))
                       ()
                       "failed document carries the error losslessly"))
             (assert-equal 2
                           (length (hackmode:list-outbox-entries hackmode:*db*))
                           "failed tool-run document enqueued too"))
           ;; Declared-but-pending tools fail cleanly without side effects.
           (let* ((response (hackmode-mcp:handle-message
                             (call-tool-request
                              22 "httpx"
                              (list :obj
                                    (cons "target" "example.com")))))
                  (result (jsval response "result")))
             (assert-equal :true (jsval result "isError")
                           "pending tool is a clean error")
             (assert (search "pending" (tool-error-message response))
                     ()
                     "pending status named in the error")
             (assert-equal 2
                           (length (hackmode:list-outbox-entries hackmode:*db*))
                           "no document for a run that never happened"))
           ;; runId validation against the declared pattern.
           (let* ((response (hackmode-mcp:handle-message
                             (call-tool-request
                              23 "nuclei"
                              (list :obj
                                    (cons "target" "example.com")
                                    (cons "runId" "BAD ID!"))))))
             (assert-equal :true (jsval (jsval response "result") "isError")
                           "invalid runId rejected")
             (assert (search "pattern" (tool-error-message response))
                     ()
                     "pattern named in the rejection"))
           ;; Server-generated runId matches the declared pattern.
           (register-fake-nuclei :success)
           (let* ((response (hackmode-mcp:handle-message
                             (call-tool-request
                              24 "nuclei"
                              (list :obj
                                    (cons "target" "example.com")))))
                  (tool-run (jsval
                             (jsval (jsval response "result")
                                    "structuredContent")
                             "toolRun"))
                  (pattern (getf (hackmode-mcp::pentest-declaration
                                  :scalar "run-id")
                                 :pattern)))
             (assert-true (cl-ppcre:scan pattern (jsval tool-run "runId"))
                          "generated runId matches the declared pattern")))
      (progn
        (close-quietly hackmode:*db*)
        (hackmode:clear-capability-providers)
        ;; Restore the load-time registrations like the sibling suites.
        (hackmode-starlang:register-pentest-providers)
        (remove-test-path root)))))

;;;; Asset projection.

(defun run-projection-test ()
  (let ((domain (hackmode:normalize-asset
                 (make-instance 'hackmode:domain
                                :record "example.com" :record-type "a"
                                :ips '("192.0.2.1")))))
    (let ((view (hackmode-mcp:project-asset domain)))
      (assert-equal "domain" (jsval view "kind") "domain kind")
      (assert-equal "example.com" (jsval view "name") "domain name")
      (assert-equal "A" (jsval view "recordType") "record type normalized")
      (assert-equal '("192.0.2.1") (jsval view "ips") "resolved ips")))
  (let ((finding (make-instance 'hackmode:finding
                                :document-id "parent"
                                :finding-type "nuclei-finding"
                                :data "exact line")))
    (let ((view (hackmode-mcp:project-asset finding)))
      (assert-equal "finding" (jsval view "kind") "finding kind")
      (assert-equal "exact line" (jsval view "data")
                    "finding data untouched"))))

(defun restore-providers ()
  "Restore the load-time registrations like the sibling suites do."
  (hackmode-starlang:register-pentest-providers)
  (let ((register (find-symbol "REGISTER-MASSDNS-PROVIDER"
                               :hackmode-provider-dns)))
    (when (and register (fboundp register))
      (funcall register))))

(defun run-tests ()
  ;; Suite order must not matter: earlier CI suites (e.g. the DNS
  ;; provider suite) leave the global provider registry partially
  ;; cleared, so re-establish the load-time registrations before any
  ;; catalog/backend assertions.
  (restore-providers)
  (run-schema-derivation-test)
  (run-catalog-test)
  (run-protocol-test)
  (run-operation-tools-test)
  (run-run-tool-test)
  (run-projection-test)
  ;; The run-tool suite cleared the registry; leave the image with the
  ;; load-time registrations restored.
  (restore-providers)
  (format t "Hackmode MCP tests passed.~%")
  t)
