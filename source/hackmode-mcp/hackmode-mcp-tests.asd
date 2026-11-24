(asdf:defsystem :hackmode-mcp-tests
  :description "Regression tests for the Hackmode MCP surface"
  :depends-on (#:hackmode-mcp
               #:hackmode-provider-dns
               #:hackmode-provider-recon
               #:tek9
               #:nhooks
               #:jsown)
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "tests"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :hackmode-mcp-tests :run-tests)))
