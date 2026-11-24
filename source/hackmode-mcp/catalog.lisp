(in-package :hackmode-mcp)

;;;; The MCP tool catalog.
;;;;
;;;; Run tool definitions are derived from the Star-Lang pentest messages
;;;; (same graph the runtime executes against); the fixed tools wrap the
;;;; canonical operation/asset surface. Handlers live in dispatch.lisp.

(defstruct mcp-tool
  name title description input-schema annotations handler)

(defparameter *server-name* "hackmode-mcp")
(defparameter *server-version* "0.1.0")

(defun run-tool-name (message-name)
  "MCP tool name for a Star-Lang message: hyphens become underscores."
  (substitute #\_ #\- message-name))

(defun fixed-tool (name title description handler read-only-p)
  (make-mcp-tool
   :name name
   :title title
   :description description
   :input-schema (list :obj (cons "type" "object") (cons "properties" (list :obj)))
   :annotations (list :obj
                      (cons "readOnlyHint" (if read-only-p :true :false))
                      (cons "destructiveHint" :false))
   :handler handler))

(defun query-tool (name title description schema handler read-only-p)
  (make-mcp-tool
   :name name
   :title title
   :description description
   :input-schema schema
   :annotations (list :obj
                      (cons "readOnlyHint" (if read-only-p :true :false))
                      (cons "destructiveHint" :false))
   :handler handler))

(defun object-tool-schema (properties required)
  "Input schema for tools taking named arguments."
  (list :obj
        (cons "type" "object")
        (cons "properties" (cons :obj properties))
        (cons "required" required)))

(defun run-tool-definition (message-name)
  "Derive the MCP tool for one declared Star-Lang message."
  (let* ((kind (if (member message-name
                           '("run-recon-tool" "recon-tool-completed")
                           :test #'string=)
                   "recon"
                   "vuln"))
         (description
           (format nil
                   "Run the declared pentest tool selected by the \"tool\" enum (~a pass) against \"target\" through Hackmode's canonical provider path. Requires an open operation store (call op_use first). Synchronous in this slice: the result carries the persisted job outcome and the encoded tool-run document. Executes external security tooling - authorized targets only."
                   kind)))
    (query-tool
     (run-tool-name message-name)
     (format nil "Hackmode ~a tool run" kind)
     description
     (message-input-schema message-name)
     (lambda (arguments) (run-declared-tool arguments))
     nil)))

(defun fixed-tools ()
  (list
   (fixed-tool
    "op_list" "List Hackmode operations"
    "List persisted Hackmode operations and the current selection."
    #'op-list-handler t)
   (fixed-tool
    "op_create" "Create a Hackmode operation"
    "Create and persist an operation. Default workspace root is ~/hackmode/<name> (override with HACKMODE_OPERATIONS_DIR or an explicit path)."
    #'op-create-handler nil)
   (fixed-tool
    "op_use" "Select the current Hackmode operation"
    "Select an operation as current and open its local store; run tools and asset queries are scoped to it."
    #'op-use-handler nil)
   (fixed-tool
    "op_status" "Show the current operation"
    "Detail for the current operation, or null when none is selected."
    #'op-status-handler t)
   (query-tool
    "asset_query" "Query operation assets"
    "List the operation's persisted typed assets, optionally filtered by asset type (domain, host, url, finding, certificate, port). An explicit positive limit bounds the response and is reported, never silent."
    (object-tool-schema
     (list (cons "type" (list :obj (cons "type" "string")))
           (cons "limit" (list :obj (cons "type" "integer"))))
     '())
    #'asset-query-handler t)
   (fixed-tool
    "capability_list" "List Hackmode capabilities and declared tools"
    "Registered capability providers plus the Star-Lang-declared pentest tool catalog with backend readiness (registered or pending)."
    #'capability-list-handler t)))

(defun run-tools ()
  (list (run-tool-definition "run-recon-tool")
        (run-tool-definition "run-vuln-scan")))

(defun tool-definitions ()
  "Return the full derived tool catalog."
  (append (fixed-tools) (run-tools)))

(defun find-tool (name)
  "Return the tool definition named NAME, or NIL."
  (find name (tool-definitions) :key #'mcp-tool-name :test #'string=))

(defun call-tool (name arguments)
  "Invoke tool NAME with jsown ARGUMENTS; return (values object error-p).

The object is the structuredContent of the tool result; error-p marks a
tool execution error (isError true) as opposed to a protocol error."
  (let ((tool (find-tool name)))
    (unless tool
      (error "Unknown tool ~a." name))
    (funcall (mcp-tool-handler tool) arguments)))
