(asdf:defsystem :hackmode-actors
  :description "StarLang ontology-driven actor system for Hackmode StarIntel integration"
  :author "nsaspy"
  :license "LGLv3"
  :version "0.1.0"
  :serial t
  :in-order-to ((test-op (test-op "hackmode-actors-tests")))
  :depends-on (#:hackmode
               #:hackmode-database
               #:starintel
               #:starlang-compiler
               #:starlang-prototype
               #:star-sento-compat
               #:jsown
               #:local-time
               #:ironclad)
  :components ((:file "package")
               (:file "ontology")
               (:file "projection")
               (:file "actors")))
