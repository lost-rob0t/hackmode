(asdf:defsystem :recon-github
  :description "Hackmode tool for github osint"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.1.0"
  :serial t
  :depends-on (:jsown :github-api-cl)
  :components ((:file "github-recon")))
