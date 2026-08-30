(asdf:defsystem :hackmode-tests
  :description "Regression tests for Hackmode core state, asset lifecycle, and expert reasoning"
  :depends-on (#:hackmode)
  :serial t
  :components ((:file "tests/core-state")
               (:file "tests/expert")
               (:file "tests/expert-orchestration"))
  :perform (test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :hackmode-tests :run-tests)
             (uiop:symbol-call :hackmode-tests :run-expert-tests)
             (uiop:symbol-call :hackmode-tests :run-expert-orchestration-tests)))
