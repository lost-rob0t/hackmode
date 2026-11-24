(uiop:define-package :hackmode-mcp
  (:use :cl)
  (:nicknames :hackmode.mcp)
  (:documentation
   "MCP stdio surface over the canonical Hackmode operation runtime.

Tool definitions are derived from the Star-Lang pentest library and the
fixed operation/asset surface; dispatch calls canonical Hackmode APIs
only. The server owns no durable state.")
  (:export
   :*server-name*
   :*server-version*
   :*latest-protocol-version*
   :supported-protocol-versions
   :mcp-tool
   :mcp-tool-name
   :mcp-tool-title
   :mcp-tool-description
   :mcp-tool-input-schema
   :mcp-tool-annotations
   :mcp-tool-handler
   :tool-definitions
   :find-tool
   :*declared-tool-backends*
   :tool-backend-status
   :resolve-type-schema
   :message-input-schema
   :project-asset
   :call-tool
   :handle-message
   :handle-line
   :run-server
   :main))

(in-package :hackmode-mcp)
