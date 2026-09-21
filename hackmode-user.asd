(asdf:defsystem :hackmode-user
  :version "0.2.0"
  :description "Hackmode command-line and Lish expert-shell entry points"
  :author "nsaspy@airmail.cc"
  :serial t
  :license "LGPLv3"
  :components ((:file "hackmode"))
  :depends-on (#:hackmode
               #:hackmode-provider-dns
               #:hackmode-provider-recon
               #:lish
               #:shellpool))
