(uiop:define-package :hackmode-starlang
  (:use :cl)
  (:nicknames :hackmode.starlang)
  (:export
   :*pentest-graph*
   :*default-dataset*
   :*nuclei-program*
   :pentest-spec-pathname
   :load-pentest-graph
   :pentest-library-name
   :pentest-library-version
   :pentest-declarations
   :pentest-enum-values
   :pentest-declaration-fields
   :declared-tools
   :declared-recon-tools
   :declared-vuln-tools
   :tool-kind-for
   :make-tool-run-document
   :encode-tool-run
   :make-vuln-finding-document
   :encode-vuln-finding
   :parse-nuclei-output
   :run-nuclei
   :nuclei-findings
   :register-nuclei-provider
   :register-pentest-providers))

(in-package :hackmode-starlang)
