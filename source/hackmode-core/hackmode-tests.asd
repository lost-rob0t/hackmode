(asdf:defsystem :hackmode-tests
  :description "Regression tests for Hackmode core state, asset lifecycle, expert reasoning, and RAGE worker scope"
  :depends-on (#:hackmode)
  :serial t
  :components ((:file "tests/core-state")
               (:file "tests/expert")
               (:file "tests/rage-worker"))
  :perform (test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :hackmode-tests :run-tests)
             (uiop:symbol-call :hackmode-tests :run-expert-tests)
             (uiop:symbol-call :hackmode-tests :run-rage-worker-tests)))
