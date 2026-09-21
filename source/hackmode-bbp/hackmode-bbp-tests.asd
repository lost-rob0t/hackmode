(asdf:defsystem :hackmode-bbp-tests
  :description "Tests for Hackmode BBP actor service execution"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.1.0"
  :serial t
  :depends-on (#:hackmode-bbp)
  :components ((:module "tests"
                :serial t
                :components ((:file "bbp-tests"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :hackmode-bbp-tests :run-tests)))
