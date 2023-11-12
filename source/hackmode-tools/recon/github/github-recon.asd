(asdf:defsystem :github-recon
  :description "Hackmode tool for github osint"
  :author "nsaspy"
  :license "LGLV3"
  :version "0.1.0"
  :serial t
  :depends-on (#:dexador :jsown :github-api-cl)
  :components ((:file "github-recon")))
