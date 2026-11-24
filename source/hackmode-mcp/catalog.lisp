(in-package :hackmode-mcp)

;;;; The MCP tool catalog.
;;;;
;;;; One Star-Lang-declared pentest tool defines exactly one MCP tool,
;;;; named verbatim; composed convenience tools are allowed only as
;;;; future ADDITIONS, never replacements (operator directive
;;;; 2026-11-24: every declared tool must remain individually callable).
;;;; The fixed tools wrap the canonical operation/asset surface.
;;;; Handlers live in dispatch.lisp.

(defstruct mcp-tool
  name title description input-schema annotations handler)

(defparameter *server-name* "hackmode-mcp")
(defparameter *server-version* "0.1.0")

(defun declared-tool-input-schema (tool kind)
  "Per-tool input schema: the declared message schema minus the tool
selector, because the MCP tool IS the declared tool (one Hackmode tool
defines exactly one callable MCP tool, named verbatim)."
  (let* ((message-name (if (string= kind "recon")
                           "run-recon-tool"
                           "run-vuln-scan"))
         (schema (message-input-schema message-name))
         (properties (jsown:val-safe schema "properties"))
         (required (jsown:val-safe schema "required")))
    (list :obj
          (cons "type" "object")
          (cons "properties"
                ;; properties is (:OBJ entry ...): keep the tag, drop the
                ;; tool selector entry.
                (cons :obj
                      (remove "tool" (cdr properties)
                              :key #'car :test #'string=)))
          (cons "required"
                (remove "tool" required :test #'string=)))))

(defun declared-tool-definition (tool)
  "Derive the MCP tool for one Star-Lang-declared pentest TOOL.

Identity is the declared name verbatim; the call runs exactly this one
tool through the canonical provider path. Composite tools, if ever
added, must come on top of these, never instead of them."
  (let ((kind (string-downcase (string (hackmode-starlang:tool-kind-for tool)))))
    (make-mcp-tool
     :name tool
     :title (format nil "Hackmode ~a: ~a" kind tool)
     :description
     (format nil
             "Run the declared pentest tool ~a (org.hackmode/pentest@1, ~a pass) against \"target\" through Hackmode's canonical provider path. One call runs exactly this one tool. Requires an open operation store (call op_use first). Synchronous in this slice: the result carries the persisted job outcome and the encoded tool-run document. Executes external security tooling - authorized targets only."
             tool kind)
     :input-schema (declared-tool-input-schema tool kind)
     :annotations (list :obj
                        (cons "readOnlyHint" :false)
                        (cons "destructiveHint" :false))
     :handler (lambda (arguments) (run-declared-tool tool arguments)))))

(defun run-tools ()
  "One MCP tool per declared pentest tool, derived from the graph."
  (mapcar #'declared-tool-definition (hackmode-starlang:declared-tools)))

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
