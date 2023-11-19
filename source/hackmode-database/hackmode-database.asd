(asdf:defsystem :hackmode-database
  :description "Database for hackmode"
  :author "nsaspy"
  :license "MIT"
  :version "0.1.0"
  :serial t

  :depends-on (#:tek9 #:cl-conspack)
  :components ((:file "package")
               (:file "objects")
               (:file "encoding")
               (:file "db")))
