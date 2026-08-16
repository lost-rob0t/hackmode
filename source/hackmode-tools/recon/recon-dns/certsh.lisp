(in-package :recon.dns)

(defun cert.sh (domain)
  "Return unique domain names observed by crt.sh for DOMAIN."
  (remove-duplicates
   (flatten
    (loop for result in
            (jsown:parse
             (dex:get
              (format nil "https://crt.sh/?q=~a&output=json" domain)
              :headers '(("User-Agent" . "Hackmode")
                         ("Accept" . "Application/json"))))
          for name = (jsown:val result "name_value")
          unless (str:containsp "@" name)
            collect
            (str:words
             (cl-ppcre:regex-replace-all "\\*\\." name ""))))
   :test #'string=))

(defvar *cert.sh-setup-hook*
  (make-instance 'nhooks:hook-void :handlers nil)
  "Hook called before crt.sh lookup runs.")

(defvar *cert.sh-finish-hook*
  (make-instance 'nhooks:hook-any :handlers nil)
  "Hook called with the list of discovered DOMAIN objects.")

(defun cert.sh* (domain)
  "Query crt.sh and route domains through Hackmode's canonical asset lifecycle."
  (nhooks:run-hook *cert.sh-setup-hook*)
  (let ((response
          (loop for name in (cert.sh domain)
                unless (string= name "")
                  collect
                  (multiple-value-bind (stored created-p persisted-p)
                      (record-recon-asset
                       (make-instance 'domain
                                      :record name
                                      :tool "crt.sh"
                                      :tags '("crt.sh" "domain")))
                    (declare (ignore created-p persisted-p))
                    stored))))
    (nhooks:run-hook *cert.sh-finish-hook* response)
    response))

(lish:defcommand cert.sh ((domain string))
  (loop for result in (cert.sh* domain)
        do (format t "~a~%" (domain-name result))))
