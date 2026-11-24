(asdf:defsystem :hackmode-mcp
  :description "MCP stdio surface over the canonical Hackmode operation runtime"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.1.0"
  :serial t
  :in-order-to ((test-op (test-op "hackmode-mcp-tests")))
  :depends-on (#:hackmode
               #:hackmode-starlang
               #:tek9
               #:nhooks
               #:cl-ppcre
               #:jsown)
  :components ((:file "package")
               (:file "schema")
               (:file "project")
               (:file "dispatch")
               (:file "catalog")
               (:file "transport")
               (:file "server")))
