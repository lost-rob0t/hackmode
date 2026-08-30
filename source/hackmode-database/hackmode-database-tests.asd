(asdf:defsystem :hackmode-database-tests
  :description "Regression tests for Hackmode database graph/KB persistence"
  :depends-on (#:hackmode-database)
  :serial t
  :components ((:file "tests/execution-graph")
               (:file "tests/long-term-kb")
               (:file "tests/global-kb")
               (:file "tests/replay-conflict")
               (:file "tests/kb-seed-import")
               (:file "tests/execution-outcome-kb")
               (:file "tests/effective-operational-kb")
               (:file "tests/http-exchange-graph"))
  :perform (test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :hackmode-database-tests :run-tests)
             (uiop:symbol-call :hackmode-database-tests :run-long-term-kb-tests)
             (uiop:symbol-call :hackmode-database-tests :run-global-kb-tests)
             (uiop:symbol-call :hackmode-database-tests :run-replay-conflict-tests)
             (uiop:symbol-call :hackmode-database-tests :run-kb-seed-import-tests)
             (uiop:symbol-call :hackmode-database-execution-outcome-tests
                               :run-execution-outcome-kb-tests)
             (uiop:symbol-call :hackmode-database-tests
                               :run-effective-operational-kb-tests)
             (uiop:symbol-call :hackmode-database-tests
                               :run-http-exchange-graph-tests)))
