(asdf:defsystem :hackmode
  :description "Core Systems for hackmode"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.3.0"
  :serial t
  :in-order-to ((test-op (test-op "hackmode-tests")))
  :depends-on (#:serapeum
               :local-time
               :nfiles
               :nhooks
               #:bordeaux-threads
               #:tek9
               #:hackmode-database
               #:starintel
               #:jsown
               #:cl-ppcre
               #:dexador
               #:sento
               #:shellpool)
  :components ((:file "package")
               (:file "utils")
               (:file "settings")
               (:file "objects")
               (:file "database")
               (:file "operations")
               (:file "assets")
               (:file "starintel-documents")
               (:file "actor-system")
               (:file "outbox")
               (:file "outbox-actor")
               (:file "providers")
               (:file "provider-actor")
               (:file "expert")
               (:module "expert-actions"
                :pathname "expert/"
                :serial t
                :components ((:file "actions")
                             (:file "orchestration")
                             (:file "state-snapshot")
                             (:file "plan")
                             (:file "recon")
                             (:file "loop")
                             (:file "objective")
                             (:file "extension")
                             (:file "selection")
                             (:file "budget")
                             (:file "budget-loop")
                             (:file "inspection")))
               (:file "functions")
               (:file "exploits")
               (:file "hackmode")))
