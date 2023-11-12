(asdf:defsystem :hackmode-tui
  :description "TUI Interface to hackmode"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.1.0"
  :serial t
  :depends-on (#:alexandria #:serapeum :hackmode  #:cl-tui #:nhooks #:nfiles)
  :components ((:file "package")
               (:file "tui")))
