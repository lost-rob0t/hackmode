(asdf:defsystem :hackmode
  :description "Core Systems for hackmode"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.1.0"
  :serial t
  :depends-on (#:serapeum :local-time :nfiles :nhooks #:tek9 #:cl-ppcre)
  :components ((:file "package")
               (:file "utils")
               (:file "settings")
               (:file "objects")
               (:file "database")
               (:file "functions")
               (:file "exploits")
               (:file "hackmode")))
