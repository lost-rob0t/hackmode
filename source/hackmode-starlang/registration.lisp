(in-package :hackmode-starlang)

(eval-when (:load-toplevel :execute)
  ;; Load-time registration, matching the sibling provider systems
  ;; (hackmode-provider-recon registration.lisp, hackmode-provider-dns
  ;; massdns.lisp): a product image containing this system can resolve
  ;; :vuln-scan immediately.
  (register-pentest-providers))
