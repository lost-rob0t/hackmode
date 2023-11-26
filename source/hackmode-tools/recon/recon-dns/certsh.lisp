(in-package :recon.dns)


(defun cert.sh (domain)
  (remove-duplicates (flatten (loop for result in  (jsown:parse (dex:get (format nil "https://crt.sh/?q=~a&output=json" domain) :headers '(("User-Agent" . "Hackmode") ("Accept" . "Application/json"))))
                                    for domain = (jsown:val result "name_value")
                                    if (not (str:containsp "@" domain))
                                      collect (str:words (cl-ppcre:regex-replace-all "\\*\\."  domain "")))) :test #'string=))


(defvar *cert.sh-setup-hook* (make-instance 'nhooks:hook-void
                                            :handlers nil)
  "Hook That is called before cert.sh is ran.")

(defvar *cert.sh-finish-hook* (make-instance 'nhooks:hook-any
                                             :handlers nil)
  "Hook That is called after cert.sh is finished. Argument must accept list of DOMAIN objects.")



(defun cert.sh* (domain)
  (nhooks:run-hook *cert.sh-setup-hook*)
  (let ((resp (loop for domain in (cert.sh domain)
                    for result = (make-instance 'domain :id (format nil "~a" (sxhash domain)) :record domain  :tool "cert.sh" :tags '("crt.sh" "domain"))
                    do (nhooks:run-hook *domain-hook* result)
                    collect result)))

    (nhooks:run-hook *cert.sh-finish-hook* resp)
    resp))

(lish:defcommand cert.sh ((domain string))
  (loop for domain in  (cert.sh* domain)
        do (format t "~a~%" (domain-name domain))))
