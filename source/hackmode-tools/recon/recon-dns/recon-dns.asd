(asdf:defsystem :recon-dns
  :version      "0.1.0"
  :description  "DNS recon tooling."
  :author       "nsaspy@airmail.cc"
  :serial       t
  :license      "LGPLV3"
  :components   ((:file "package")
                 (:file "dns")
                 (:file "mdi")
                 (:file "certsh"))
  :depends-on   (#:hackmode #:lish #:str #:shellpool #:dexador #:lquery #:lparallel #:xmls))
