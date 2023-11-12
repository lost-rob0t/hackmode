(asdf:defsystem :hackmode
  :description "Core Systems for hackmode"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.1.0"
  :serial t
  :depends-on (#:alexandria #:serapeum :local-time :nfiles :nhooks #:defstar)
  :components ((:file "package")
               (:file "utils")
               (:file "settings")
               (:file "history")
               (:file "exploits")
               (:file "hackmode")))
