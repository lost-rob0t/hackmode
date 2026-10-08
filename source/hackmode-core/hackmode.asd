(asdf:defsystem "hackmode/modules"
  :description "Dependency-free module metadata, registry, and local catalog protocol"
  :serial t
  :in-order-to ((test-op (test-op "hackmode/module-tests")))
  :components ((:file "modules-package")
               (:file "modules")
               (:file "module-catalog")))

(asdf:defsystem "hackmode/module-tests"
  :description "Dependency-free module catalog regression tests"
  :depends-on ("hackmode/modules")
  :serial t
  :components ((:file "tests/modules"))
  :perform (test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :hackmode-module-tests :run-module-tests)))

(asdf:defsystem :hackmode
  :description "Core Systems for hackmode"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.3.0"
  :serial t
  :in-order-to ((test-op (test-op "hackmode-tests")))
  :depends-on (#:hackmode/modules
               #:serapeum
               :local-time
               :nfiles
               :nhooks
               #:bordeaux-threads
               #:tek9
               #:hackmode-database
               #:starintel
               #:jsown
               #:cl-ppcre
               #:ironclad
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
               (:file "module-actor")
               (:file "outbox")
               (:file "investigation-views")
               (:file "visual-evidence-outbox")
               (:file "outbox-actor")
               (:file "http-transport-profile")
               (:file "http-requester")
               (:file "providers")
               (:file "provider-actor")
               (:file "capture-provider")
               (:file "capture-replay")
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
                             (:file "direct-candidate")
                             (:file "objective")
                             (:file "extension")
                             (:file "selection")
                             (:file "budget")
                             (:file "budget-loop")
                             (:file "inspection")
                             (:file "inspection-accessors")
                             (:file "transition-inspection")
                             (:file "selection-inspection")
                             (:file "budget-inspection")))
               (:file "functions")
               (:file "exploits")
               (:file "hackmode")))
