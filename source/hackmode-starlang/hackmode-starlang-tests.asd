(asdf:defsystem :hackmode-starlang-tests
  :description "Regression tests for the Star-Lang pentest tool bridge"
  :depends-on (#:hackmode-starlang #:hackmode-provider-recon)
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "tests"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :hackmode-starlang-tests :run-tests)))
