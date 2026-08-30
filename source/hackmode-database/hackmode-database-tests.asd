(asdf:defsystem :hackmode-database-tests
  :description "Regression tests for Hackmode database graph/KB persistence"
  :depends-on (#:hackmode-database)
  :serial t
  :components ((:file "tests/execution-graph"))
  :perform (test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :hackmode-database-tests :run-tests)))
