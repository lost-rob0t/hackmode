(asdf:defsystem :hackmode-starintel-commands
  :description "Interactive LISH commands for the Hackmode StarIntel integration"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.3.0"
  :serial t
  :depends-on (#:hackmode #:lish)
  :components ((:file "starintel-commands")))
