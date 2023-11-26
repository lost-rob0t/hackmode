(uiop:define-package   :recon-dns
  (:use :cl :hackmode)
  (:nicknames :recon.dns)
  (:export
   :dns-recon
   :subfinder
   :subfinder*
   :dnsrecon
   :check-mdi
   :*subfinder-finish-hook*
   :*subfinder-setup-hook*
   :*cert.sh-finish-hook*
   :*cert.sh-setup-hook*
   :*oam-subs-setup-hook*
   :*oam-subs-finish-hook*
   :oam-subs
   :oam-subs*
   :cert.sh*
   :cert.sh
   :check-mdi*
   :*check-mdi-finish-hook*
   :*check-mdi-setup-hook*)

  (:documentation "DNS recon tooling"))
