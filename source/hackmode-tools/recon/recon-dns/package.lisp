(uiop:define-package   :recon-dns
  (:use :cl :hackmode)
  (:nicknames :recon.dns)
  (:export
   :amass
   :dns-recon
   :subfinder
   :subfinder*
   :amass*
   :dnsrecon
   :check-mdi
   :*subfinder-finish-hook*
   :*subfinder-setup-hook*)

  (:documentation "DNS recon tooling"))
