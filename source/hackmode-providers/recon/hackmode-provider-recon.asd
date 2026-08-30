(asdf:defsystem :hackmode-provider-recon
  :description "Concrete typed recon providers for Hackmode"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.1.0"
  :serial t
  :in-order-to ((test-op (test-op "hackmode-provider-recon-tests")))
  :depends-on (#:hackmode #:jsown #:dexador)
  :components ((:file "package")
               (:file "recon")))
