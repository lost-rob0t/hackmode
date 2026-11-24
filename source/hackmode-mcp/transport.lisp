(in-package :hackmode-mcp)

;;;; MCP transport: newline-delimited JSON-RPC 2.0 over stdio.
;;;;
;;;; Protocol facts are pinned to the MCP specification (2025-06-18 tools
;;;; page fetched in full; version negotiation is a date string at
;;;; initialize; protocol errors are JSON-RPC errors while tool execution
;;;; errors are results with isError true). Logs go to stderr; stdout
;;;; carries protocol traffic only.

(defparameter *supported-protocol-versions* '("2024-11-05" "2025-06-18")
  "Protocol versions this server speaks. The tool surface used here is
identical across them; 2026-07-28 (resultType emission) is a recorded
upgrade path, not a partial pretense.")

(defparameter *latest-protocol-version* "2025-06-18")

(defun json-object (&rest pairs)
  (cons :obj pairs))

(defun protocol-error (id code message)
  (declare (ignore id))
  (list :obj (cons "code" code) (cons "message" message)))

(defun error-response (id error)
  (list :obj
        (cons "jsonrpc" "2.0")
        (cons "id" (or id :null))
        (cons "error" error)))

(defun response (id result)
  (list :obj
        (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "result" result)))

(defun initialize-result (params)
  (let* ((requested (and params (jsown:val-safe params "protocolVersion")))
         (version (if (member requested *supported-protocol-versions*
                              :test #'string=)
                      requested
                      *latest-protocol-version*)))
    (list :obj
          (cons "protocolVersion" version)
          (cons "capabilities"
                (list :obj
                      (cons "tools"
                            (list :obj (cons "listChanged" :false)))))
          (cons "serverInfo"
                (list :obj
                      (cons "name" *server-name*)
                      (cons "version" *server-version*))))))

(defun tool-definition-json (tool)
  (list :obj
        (cons "name" (mcp-tool-name tool))
        (cons "title" (mcp-tool-title tool))
        (cons "description" (mcp-tool-description tool))
        (cons "inputSchema" (mcp-tool-input-schema tool))
        (cons "annotations" (mcp-tool-annotations tool))))

(defun text-content (text)
  (list :obj (cons "type" "text") (cons "text" text)))

(defun call-tool-result (object error-p)
  "Build the CallToolResult for one tool outcome.

structuredContent carries the complete result object; the same JSON is
echoed in a text block per the spec's back-compatibility rule."
  (list :obj
        (cons "content" (list (text-content (jsown:to-json object))))
        (cons "structuredContent" object)
        (cons "isError" (if error-p :true :false))))

(defun handle-tools-call (id params)
  (let ((name (and params (jsown:val-safe params "name"))))
    (cond
      ((not (stringp name))
       (error-response id
                       (protocol-error id -32602
                                       "tools/call params.name must be a string.")))
      ((null (find-tool name))
       (error-response id
                       (protocol-error id -32602
                                       (format nil "Unknown tool ~a." name))))
      (t
       (let ((arguments (and params (jsown:val-safe params "arguments"))))
         (multiple-value-bind (object error-p)
             (handler-case
                 (call-tool name (or arguments (json-object)))
               (error (condition)
                 (values (json-object
                          (cons "error" (format nil "~a" condition)))
                         t)))
           (response id (call-tool-result object (and error-p t)))))))))

(defun handle-message (message)
  "Handle one decoded JSON-RPC message; return the response object, or
NIL for notifications and other messages that must not be answered."
  (when (and (consp message) (eq (first message) :obj))
    (let ((method (jsown:val-safe message "method"))
          (id (jsown:val-safe message "id")))
      (cond
        ((and (stringp method) (string= method "initialize"))
         (response id
                   (initialize-result (jsown:val-safe message "params"))))
        ((and (stringp method) (search "notifications/" method))
         nil)
        ((null method) nil)
        ((and (stringp method) (string= method "ping"))
         (response id (json-object)))
        ((and (stringp method) (string= method "tools/list"))
         (response id
                   (json-object
                    (cons "tools"
                          (mapcar #'tool-definition-json (tool-definitions))))))
        ((and (stringp method) (string= method "tools/call"))
         (handle-tools-call id (jsown:val-safe message "params")))
        (t
         (when id
           (error-response id
                           (protocol-error id -32601
                                           (format nil "Unknown method ~a." method)))))))))

(defun handle-line (line &optional (output *standard-output*))
  "Decode one stdin LINE and write the response when one is due.

jsown's parser returns NIL for undecodable input instead of signaling, so
NIL and any signaling error both count as a parse failure. A line that
decodes to a non-object JSON value is answered with -32600 so every bad
frame gets exactly one deterministic error response."
  (let ((trimmed (string-trim '(#\Space #\Tab #\Return) line)))
    (when (plusp (length trimmed))
      (let ((message (handler-case (or (jsown:parse trimmed) :parse-error)
                       (error () :parse-error))))
        (let ((response
                (cond
                  ((eq message :parse-error)
                   (error-response nil
                                   (protocol-error nil -32700 "Parse error.")))
                  ((or (not (consp message))
                       (not (eq (first message) :obj)))
                   (error-response
                    nil
                    (protocol-error nil -32600
                                    "Requests must be JSON objects.")))
                  (t (handle-message message)))))
          (when response
            (write-line (jsown:to-json response) output)
            (finish-output output)))))))

(defun run-server (&key (input *standard-input*) (output *standard-output*))
  "Serve MCP over newline-delimited JSON-RPC 2.0 until EOF on INPUT.

Sequential by design in this slice: one tool call at a time, no retries
of effectful calls, which is the documented slice-1 rate-limit posture."
  (format *error-output*
          "~a ~a ready; protocol versions ~{~a~^, ~}; catalog derived from ~a ~a~%"
          *server-name* *server-version*
          *supported-protocol-versions*
          (hackmode-starlang:pentest-library-name)
          (hackmode-starlang:pentest-library-version))
  (finish-output *error-output*)
  (loop for line = (read-line input nil nil)
        while line
        do (handle-line line output))
  0)
