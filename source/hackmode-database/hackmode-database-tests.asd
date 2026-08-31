(asdf:defsystem :hackmode-database-tests
  :description "Regression tests for Hackmode database graph/KB persistence"
  :depends-on (#:hackmode-database)
  :serial t
  :components ((:file "tests/execution-graph")
               (:file "tests/long-term-kb")
               (:file "tests/long-term-kb-singular-fetch")
               (:file "tests/global-kb")
               (:file "tests/global-kb-canonical-source")
               (:file "tests/replay-conflict")
               (:file "tests/kb-seed-import")
               (:file "tests/execution-outcome-kb")
               (:file "tests/effective-operational-kb")
               (:file "tests/http-exchange-graph")
               (:file "tests/capture-checkpoint")
               (:file "tests/capture-quarantine")
               (:file "tests/capture-source-rotation")
               (:file "tests/operational-kb-retraction-target")
               (:file "tests/visual-evidence"))
  :perform (test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :hackmode-database-tests :run-tests)
             (uiop:symbol-call :hackmode-database-tests :run-long-term-kb-tests)
             (uiop:symbol-call :hackmode-database-tests
                               :run-long-term-kb-singular-fetch-tests)
             (uiop:symbol-call :hackmode-database-tests :run-global-kb-tests)
             (uiop:symbol-call :hackmode-database-tests
                               :run-global-kb-canonical-source-tests)
             (uiop:symbol-call :hackmode-database-tests :run-replay-conflict-tests)
             (uiop:symbol-call :hackmode-database-tests :run-kb-seed-import-tests)
             (uiop:symbol-call :hackmode-database-execution-outcome-tests
                               :run-execution-outcome-kb-tests)
             (uiop:symbol-call :hackmode-database-tests
                               :run-effective-operational-kb-tests)
             (uiop:symbol-call :hackmode-database-tests
                               :run-http-exchange-graph-tests)
             (uiop:symbol-call :hackmode-database-tests
                               :run-capture-checkpoint-tests)
             (uiop:symbol-call :hackmode-database-tests
                               :run-capture-quarantine-tests)
             (uiop:symbol-call :hackmode-database-tests
                               :run-capture-source-rotation-tests)
             (uiop:symbol-call :hackmode-database-tests
                               :run-operational-kb-retraction-target-tests)
             (uiop:symbol-call :hackmode-database-tests
                               :run-visual-evidence-tests)))