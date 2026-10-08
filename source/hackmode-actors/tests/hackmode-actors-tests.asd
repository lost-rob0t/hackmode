(asdf:defsystem :hackmode-actors-tests
  :description "Tests for the Hackmode ontology actor system"
  :author "nsaspy"
  :license "LGLv3"
  :version "0.1.0"
  :serial t
  :depends-on (#:hackmode-actors)
  :components ((:file "ontology-tests")
               (:file "projection-tests")
               (:file "actor-tests"))
  :perform (test-op (operation component)
             (uiop:symbol-call :hackmode-actors-tests :run-all-tests)))
