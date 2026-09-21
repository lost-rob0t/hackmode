(uiop:define-package :hackmode-provider-bbp
  (:use :cl)
  (:nicknames :hackmode.providers.bbp)
  (:export
   :*httpx-program*
   :*katana-program*
   :*nmap-program*
   :parse-httpx-output
   :parse-katana-output
   :parse-nmap-output
   :run-httpx
   :run-katana
   :run-nmap
   :register-httpx-provider
   :register-katana-provider
   :register-nmap-provider
   :register-bbp-providers))

(in-package :hackmode-provider-bbp)
