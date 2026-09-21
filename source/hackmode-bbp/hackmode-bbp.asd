(asdf:defsystem :hackmode-bbp
  :description "BBP actor service execution port on the Hackmode Sento runtime"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.1.0"
  :serial t
  :in-order-to ((test-op (test-op "hackmode-bbp-tests")))
  :depends-on (#:hackmode
               #:hackmode-provider-bbp
               #:sento
               #:tek9)
  :components ((:file "package")
               (:file "service")))
