(asdf:defsystem :hackmode-provider-zap
  :description "OWASP ZAP daemon backends for the Star-Lang-declared pentest tools"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.1.0"
  :serial t
  :in-order-to ((test-op (test-op "hackmode-provider-zap-tests")))
  :depends-on (#:hackmode
               #:jsown)
  :components ((:file "package")
               (:file "daemon")
               (:file "scripts")
               (:file "scanner")
               (:file "probes")
               (:file "zap")
               (:file "registration")
               (:static-file "zap-scripts/race-probe.js")
               (:static-file "zap-scripts/smuggle-probe.js")
               (:static-file "zap-scripts/jwt-toolkit.js")
               (:static-file "zap-scripts/param-miner.js")
               (:static-file "zap-scripts/authz-diff.js")
               (:static-file "zap-scripts/content-discovery.js")
               (:static-file "zap-scripts/graphql-probe.js")))
