(in-package :hackmode-provider-zap)

(eval-when (:load-toplevel :execute)
  ;; Load-time registration, matching the sibling provider systems
  ;; (hackmode-provider-recon registration.lisp, hackmode-provider-dns):
  ;; a product image containing this system can resolve the declared zap
  ;; tools immediately. Requires a reachable daemon only at RUN time.
  (register-zap-providers))
