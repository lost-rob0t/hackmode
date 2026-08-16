(asdf:defsystem :hackmode-provider-dns
  :description "Typed DNS providers for Hackmode"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.1.0"
  :serial t
  :in-order-to ((test-op (test-op "hackmode-provider-dns-tests")))
  :depends-on (#:hackmode #:jsown)
  :components ((:file "package")
               (:file "massdns")))
