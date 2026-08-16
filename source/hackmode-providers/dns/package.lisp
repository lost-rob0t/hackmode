(uiop:define-package :hackmode-provider-dns
  (:use :cl)
  (:nicknames :hackmode.providers.dns)
  (:export
   :*massdns-program*
   :*massdns-resolvers*
   :parse-massdns-json-line
   :parse-massdns-output
   :run-massdns-json
   :massdns-resolve
   :register-massdns-provider))

(in-package :hackmode-provider-dns)
