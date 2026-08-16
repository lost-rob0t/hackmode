(asdf:defsystem :hackmode-tests
  :description "Regression tests for Hackmode core state and asset lifecycle"
  :depends-on (#:hackmode)
  :serial t
  :components ((:file "tests/core-state"))
  :perform (test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :hackmode-tests :run-tests)))
