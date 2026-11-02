(asdf:defsystem :hackmode-starlang
  :description "Star-Lang pentest tool definitions bridged into Hackmode providers"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.1.0"
  :serial t
  :in-order-to ((test-op (test-op "hackmode-starlang-tests")))
  :depends-on (#:hackmode
               #:starlang-prototype
               #:jsown)
  :components ((:file "package")
               (:file "graph")
               (:file "providers")))
