(asdf:defsystem :hackmode-provider-recon-tests
  :description "Regression tests for Hackmode recon providers"
  :depends-on (#:hackmode-provider-recon)
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "recon-tests"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :hackmode-provider-recon-tests :run-tests)))
