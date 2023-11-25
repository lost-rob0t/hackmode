(asdf:defsystem :hackmode-user
  :version      "0.1.0"
  :description  "description"
  :author       "nsaspy@airmail.cc"
  :serial       t
  :license      "LGPLv3"
  :components   ((:file "hackmode"))
  :depends-on   (#:hackmode #:lish #:hackmode-tools))
