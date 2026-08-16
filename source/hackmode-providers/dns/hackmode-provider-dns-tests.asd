(asdf:defsystem :hackmode-provider-dns-tests
  :description "Regression tests for Hackmode DNS providers"
  :depends-on (#:hackmode-provider-dns)
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "massdns-tests"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :hackmode-provider-dns-tests :run-tests)))
