(asdf:defsystem :hackmode-provider-wireless-tests
  :description "Regression tests for the Hackmode wireless provider"
  :depends-on (#:hackmode-provider-wireless)
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "wireless-tests"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :hackmode-provider-wireless-tests :run-tests)))
