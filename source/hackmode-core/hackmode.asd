(asdf:defsystem :hackmode
  :description "Core Systems for hackmode"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.1.0"
  :serial t
  :depends-on (#:serapeum :local-time :nfiles :nhooks #:tek9 #:cl-ppcre #:dexador #:shellpool)
  :components ((:file "package")
               (:file "utils")
               (:file "settings")
               (:file "objects")
               (:file "database")
               (:file "operations")
               (:file "functions")
               (:file "exploits")
               (:file "hackmode")))
