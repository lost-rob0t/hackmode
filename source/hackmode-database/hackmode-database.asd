(asdf:defsystem :hackmode-database
  :description "Hackmode-owned Tek9 execution graph and KB persistence boundary"
  :author "nsaspy"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :in-order-to ((test-op (test-op "hackmode-database-tests")))
  :depends-on (#:tek9)
  :components ((:file "package")
               (:file "execution-graph")
               (:file "operational-kb")
               (:file "long-term-kb")
               (:file "global-kb")
               (:file "replay")
               (:file "db")))
