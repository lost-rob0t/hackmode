(asdf:defsystem :hackmode-provider-zap-tests
  :description "Regression tests for Hackmode ZAP daemon provider backends"
  :depends-on (#:hackmode-provider-zap
               #:hackmode
               #:jsown)
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "zap-tests"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call :hackmode-provider-zap-tests :run-tests)))
