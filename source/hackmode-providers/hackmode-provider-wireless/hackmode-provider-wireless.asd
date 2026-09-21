(asdf:defsystem :hackmode-provider-wireless
  :description "Aircrack-ng wireless capture/parse provider for Hackmode"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.1.0"
  :serial t
  :in-order-to ((test-op (test-op "hackmode-provider-wireless-tests")))
  :depends-on (#:hackmode
               #:jsown
               #:ironclad
               #:babel
               #:cl-ppcre)
  :components ((:file "package")
               (:file "identity")
               (:file "parse")
               (:file "airmon")
               (:file "airodump")
               (:file "project")
               (:static-file "casefold.txt")
               (:static-file "README.org")))
