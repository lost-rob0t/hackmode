(in-package :hackmode-mcp)

;;;; Dispatch of MCP tool calls onto canonical Hackmode APIs.
;;;;
;;;; Rules:
;;;; - only canonical APIs are called (operations, capability providers,
;;;;   assets, outbox); the server adds no mutation path of its own;
;;;; - run tools require an open operation store and fail closed otherwise,
;;;;   so evidence stays operation-scoped by construction;
;;;; - nothing here truncates, summarizes, or filters captured evidence.

(defparameter *declared-tool-backends*
  '(("subfinder" :subdomain-enumerate subfinder)
    ("crtsh" :subdomain-enumerate crtsh)
    ("massdns" :dns-resolve massdns)
    ("nuclei" :vuln-scan nuclei)
    ("nmap" nil nil)
    ("httpx" nil nil)
    ("katana" nil nil)
    ("zap" nil nil))
  "Declared Star-Lang tool name -> (capability provider), or (NIL NIL)
while the concrete backend is still pending (see
docs/architecture/pentest-tool-definitions.org).")

(defun tool-backend-status (tool)
  "Return a plist describing TOOL's backend readiness.

:status :registered carries :capability and :provider; :status :pending
or :undeclared carries :detail."
  (let ((entry (assoc tool *declared-tool-backends* :test #'string=)))
    (cond
      ((null entry)
       (list :status :undeclared
             :detail "Not declared in org.hackmode/pentest@1."))
      ((second entry)
       (if (hackmode:find-capability-provider (second entry) (third entry))
           (list :status :registered
                 :capability (second entry)
                 :provider (third entry))
           (list :status :pending
                 :detail (format nil "Backend ~a/~a is not registered in this image; load its provider system."
                                 (string-downcase (string (second entry)))
                                 (string-downcase (string (third entry)))))))
      (t
       (list :status :pending
             :detail "No concrete backend yet (pentest slice 2; see docs/architecture/pentest-tool-definitions.org).")))))

;;;; Argument helpers (arguments arrive as a jsown object or NIL).

(defun argument-value (args key)
  (and args (jsown:val-safe args key)))

(defun require-string-argument (args key)
  (let ((value (argument-value args key)))
    (unless (and (stringp value)
                 (plusp (length (string-trim '(#\Space #\Tab #\Newline #\Return)
                                             value))))
      (error "Tool argument ~a must be a non-empty string." key))
    value))

(defparameter *run-id-counter* 0
  "Process-local counter keeping server-generated runIds unique.")

(defun default-run-id ()
  "Generate a runId matching the declared org.hackmode/pentest@1 pattern."
  (format nil "hm-~d-~d" (hackmode:unix-now) (incf *run-id-counter*)))

(defun require-run-id (args)
  "Return the caller's runId or generate one, validated against the
declared run-id scalar pattern. The pinned loader does not enforce
patterns (recorded in pentest-tool-definitions.org), so the server does."
  (let ((run-id (or (argument-value args "runId") (default-run-id))))
    (let ((pattern (getf (require-declaration :scalar "run-id") :pattern)))
      (unless (and (stringp run-id) pattern (cl-ppcre:scan pattern run-id))
        (error "runId ~s does not match the declared pattern ~a."
               run-id pattern))
      run-id)))

(defun require-open-operation-store ()
  (unless (and hackmode:*db* (tek9:db-is-open-p hackmode:*db*))
    (error "No Hackmode operation store is open; call op_use to select an operation first.")))

;;;; Operation tools.

(defun default-operations-root ()
  "Root directory for op_create when the caller gives no path.

Defaults to the Emacs client's operation layout (~/hackmode/, where the
other operations live); override with HACKMODE_OPERATIONS_DIR."
  (let ((configured (uiop:getenv "HACKMODE_OPERATIONS_DIR")))
    (if (and configured (plusp (length configured)))
        (uiop:ensure-directory-pathname configured)
        (merge-pathnames "hackmode/" (user-homedir-pathname)))))

(defun operation-status-object (operation)
  (let ((status (hackmode:operation-status operation)))
    (if status
        (list :obj
              (cons "name" (getf status :name))
              (cons "description" (getf status :description))
              (cons "directory" (getf status :directory))
              (cons "active" (if (getf status :active) :true :false))
              (cons "databaseOpen"
                    (if (getf status :database-open) :true :false)))
        :null)))

(defun op-list-handler (arguments)
  (declare (ignore arguments))
  (values (list :obj
                (cons "operations"
                      (mapcar (lambda (operation)
                                (list :obj
                                      (cons "name" (hackmode:operation-name operation))
                                      (cons "description" (hackmode:operation-description operation))
                                      (cons "directory" (hackmode:operation-dir operation))))
                              (hackmode:list-operations)))
                (cons "current" (operation-status-object (hackmode:current-operation))))
          nil))

(defun op-create-handler (arguments)
  (let* ((name (require-string-argument arguments "name"))
         (description (or (argument-value arguments "description")
                          "Hackmode operation"))
         (path (or (argument-value arguments "path")
                   (namestring (merge-pathnames
                                (uiop:ensure-directory-pathname name)
                                (default-operations-root))))))
    (let ((operation (hackmode:new-operation name path description)))
      ;; new-operation persists the registry record only; scaffolding the
      ;; workspace directory is this tool's job (use-operation opens the
      ;; store inside it).
      (uiop:ensure-all-directories-exist
       (list (pathname (hackmode:operation-dir operation))))
      (values (list :obj
                    (cons "operation"
                          (operation-status-object operation)))
              nil))))

(defun op-use-handler (arguments)
  (let ((name (require-string-argument arguments "name")))
    (values (list :obj
                  (cons "operation"
                        (operation-status-object (hackmode:use-operation name))))
            nil)))

(defun op-status-handler (arguments)
  (declare (ignore arguments))
  (values (list :obj
                (cons "operation"
                      (operation-status-object (hackmode:current-operation))))
          nil))

;;;; Asset tools.

(defun asset-query-handler (arguments)
  (require-open-operation-store)
  (let* ((type (argument-value arguments "type"))
         (limit (argument-value arguments "limit"))
         (assets (hackmode:query-assets :type (and type (string type))))
         (total (length assets))
         (sliced (if (and (integerp limit) (plusp limit))
                     (let ((end (min limit total)))
                       (subseq assets 0 end))
                     assets)))
    (values (list :obj
                  (cons "count" (length sliced))
                  (cons "total" total)
                  (cons "truncated" (if (< (length sliced) total) :true :false))
                  (cons "type" (or type :null))
                  (cons "assets" (mapcar #'project-asset sliced)))
            nil)))

;;;; Capability catalog tool.

(defun capability-list-handler (arguments)
  (declare (ignore arguments))
  (let ((registered
          (mapcar (lambda (definition)
                    (list :obj
                          (cons "capability" (hackmode:capability-provider-capability definition))
                          (cons "provider" (hackmode:capability-provider-name definition))
                          (cons "priority" (hackmode:capability-provider-priority definition))
                          (cons "inputType" (input-type-name (hackmode:capability-provider-input-type definition)))
                          (cons "outputTypes" (mapcar #'input-type-name
                                                      (hackmode:capability-provider-output-types definition)))
                          (cons "status" "registered")))
                  (hackmode:list-capability-providers)))
        (declared
          (loop for tool in (hackmode-starlang:declared-tools)
                for status = (tool-backend-status tool)
                collect (list :obj
                              (cons "tool" tool)
                              (cons "kind" (hackmode-starlang:tool-kind-for tool))
                              (cons "status" (string-downcase (string (getf status :status))))
                              (cons "capability" (or (getf status :capability) :null))
                              (cons "provider" (or (getf status :provider) :null))
                              (cons "detail" (or (getf status :detail) :null))))))
    (values (list :obj
                  (cons "library"
                        (list :obj
                              (cons "name" (hackmode-starlang:pentest-library-name))
                              (cons "version" (hackmode-starlang:pentest-library-version))))
                  (cons "registered" registered)
                  (cons "declared" declared))
            nil)))

;;;; Run tools (messages run-recon-tool / run-vuln-scan).

(defun operation-name-safely ()
  (if (hackmode:current-operation)
      (hackmode:operation-name (hackmode:current-operation))
      ""))

(defun build-provider-input (definition target)
  "Build the typed provider input for a string TARGET.

The resolved definition's declared input type decides the asset class;
anything without a string-target mapping fails closed."
  (let ((input-type (hackmode:capability-provider-input-type definition)))
    (cond
      ((eq input-type 'hackmode:domain)
       (make-instance 'hackmode:domain :record target :record-type ""))
      ((eq input-type 'hackmode:url)
       (hackmode:parse-url target))
      (t
       (error "Capability input type ~a has no MCP string-target mapping."
              (input-type-name input-type))))))

(defun encode-tool-run-document (run-id tool target job)
  "Build, encode, and JSON-tag the tool-run wire document for one finished
JOB.

Status completed/failed are the only states this synchronous surface can
truthfully produce. exitCode/stdout/stderr are not fabricated: live
provider plumbing for those fields is the pentest slice 2 design. The
provider's own lossless records (exact finding lines; complete
stdout/stderr embedded in the job error) remain the evidence trail.

The raw provenance map uses string keys: map values keep their keys
verbatim through star-lang normalization, so keyword keys would leak
into the wire document. After encoding, the nested map alist is tagged
:obj because jsown serializes plain lists as JSON arrays, not objects."
  (let* ((state (hackmode:provider-job-result-state job))
         (status (if (eq state :failed) "failed" "completed"))
         (error-text (hackmode:provider-job-result-error job))
         (raw (append (list (cons "capability"
                                  (hackmode:provider-job-result-capability job))
                            (cons "provider"
                                  (hackmode:provider-job-result-provider job))
                            (cons "jobId"
                                  (hackmode:provider-job-result-id job))
                            (cons "state" (string-downcase (string state)))
                            (cons "createdCount"
                                  (hackmode:provider-job-result-created-count job))
                            (cons "operation" (operation-name-safely)))
                      (when error-text
                        (list (cons "error" error-text))))))
    (let ((encoded
            (hackmode-starlang:encode-tool-run
             (hackmode-starlang:make-tool-run-document
              run-id (hackmode-starlang:tool-kind-for tool) tool target
              (list target) status :raw raw))))
      (mapcar (lambda (entry)
                (if (string= (car entry) "raw")
                    (cons "raw" (cons :obj (cdr entry)))
                    entry))
              encoded))))

(defun enqueue-tool-run-document (encoded)
  "Durably enqueue the encoded tool-run document in the open store's
outbox. encode-tool-run-document returns the :obj-tagged document, which
jsown serializes as a JSON object payload."
  (hackmode:enqueue-starintel-json
   hackmode:*db*
   (cons :obj encoded)
   :operation (operation-name-safely)))

(defun job-result-object (job)
  (list :obj
        (cons "id" (hackmode:provider-job-result-id job))
        (cons "capability" (hackmode:provider-job-result-capability job))
        (cons "provider" (hackmode:provider-job-result-provider job))
        (cons "state" (string-downcase
                       (string (hackmode:provider-job-result-state job))))
        (cons "createdCount" (hackmode:provider-job-result-created-count job))
        (cons "assets" (mapcar #'project-asset
                               (hackmode:provider-job-result-assets job)))
        (cons "error" (or (hackmode:provider-job-result-error job) :null))))

(defun run-declared-tool (tool arguments)
  "Run one declared pentest tool through the canonical provider path.

The MCP tool binding fixes TOOL (one declared tool = one callable MCP
tool); a failed job still emits its failed tool-run document before
surfacing as a tool execution error."
  (let* ((target (require-string-argument arguments "target"))
         (run-id (require-run-id arguments))
         (backend (tool-backend-status tool)))
    (unless (eq (getf backend :status) :registered)
      (error "Pentest tool ~a is ~(~a~): ~a"
             tool (getf backend :status) (getf backend :detail)))
    (require-open-operation-store)
    (let* ((definition (hackmode:find-capability-provider
                        (getf backend :capability) (getf backend :provider)))
           (input (build-provider-input definition target))
           (job (hackmode:run-capability
                 (getf backend :capability) input
                 :provider (getf backend :provider)
                 :database hackmode:*db*))
           (encoded (encode-tool-run-document run-id tool target job)))
      (enqueue-tool-run-document encoded)
      (values (list :obj
                    (cons "toolRun" (cons :obj encoded))
                    (cons "job" (job-result-object job)))
            (eq (hackmode:provider-job-result-state job) :failed)))))
