(asdf:defsystem :recon-dns
  :version      "0.1.0"
  :description  "DNS recon tooling."
  :author       "nsaspy@airmail.cc"
  :serial       t
  :license      "LGPLV3"
  :components   ((:file "dns"))
  :depends-on   (#:hackmode #:shellpool #:dexador #:lquery #:lparallel))
