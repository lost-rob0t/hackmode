(asdf:defsystem :hackmode
  :description "Core Systems for hackmode"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.2.0"
  :serial t
  :in-order-to ((test-op (test-op "hackmode-tests")))
  :depends-on (#:serapeum
               :local-time
               :nfiles
               :nhooks
               #:tek9
               #:starintel
               #:jsown
               #:cl-ppcre
               #:dexador
               #:shellpool)
  :components ((:file "package")
               (:file "utils")
               (:file "settings")
               (:file "objects")
               (:file "database")
               (:file "operations")
               (:file "assets")
               (:file "starintel-documents")
               (:file "functions")
               (:file "exploits")
               (:file "hackmode")))
