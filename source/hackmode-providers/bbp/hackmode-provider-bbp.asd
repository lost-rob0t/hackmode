(asdf:defsystem :hackmode-provider-bbp
  :description "Typed Hackmode providers required by the BBP actor service"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.1.0"
  :serial t
  :depends-on (#:hackmode
               #:hackmode-provider-recon
               #:hackmode-provider-dns
               #:jsown
               #:cl-ppcre)
  :components ((:file "package")
               (:file "providers")))
