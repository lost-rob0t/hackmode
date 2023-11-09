(asdf:defsystem :hackmode
  :description "Core Systems for hackmode"
  :author "nsaspy"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on (#:alexandria #:serapeum #:nfiles)
  :components ((:file "package")
               (:file "vars")
               (:file "settings")
               (:file "history")
               (:file "objects")))
