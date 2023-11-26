(in-package :recon.dns)

(defvar *check-mdi-setup-hook* (make-instance 'nhooks:hook-void
                                              :handlers nil)
  "Hook That is called before check-mdi is ran.")

(defvar *check-mdi-finish-hook* (make-instance 'nhooks:hook-any
                                               :handlers nil)
  "Hook That is called after check-mdi is finished. Argument must accept list of DOMAIN objects.")



(defun make-mdi-body (domain)
  (format nil "<?xml version=\"1.0\" encoding=\"utf-8\"?>
    <soap:Envelope xmlns:exm=\"http://schemas.microsoft.com/exchange/services/2006/messages\"
        xmlns:ext=\"http://schemas.microsoft.com/exchange/services/2006/types\"
        xmlns:a=\"http://www.w3.org/2005/08/addressing\"
        xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\"
        xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">
    <soap:Header>
        <a:RequestedServerVersion>Exchange2010</a:RequestedServerVersion>
        <a:MessageID>urn:uuid:6389558d-9e05-465e-ade9-aae14c4bcd10</a:MessageID>
        <a:Action soap:mustUnderstand=\"1\">http://schemas.microsoft.com/exchange/2010/Autodiscover/Autodiscover/GetFederationInformation</a:Action>
        <a:To soap:mustUnderstand=\"1\">https://autodiscover.byfcxu-dom.extest.microsoft.com/autodiscover/autodiscover.svc</a:To>
        <a:ReplyTo>
        <a:Address>http://www.w3.org/2005/08/addressing/anonymous</a:Address>
        </a:ReplyTo>
    </soap:Header>
    <soap:Body>
        <GetFederationInformationRequestMessage xmlns=\"http://schemas.microsoft.com/exchange/2010/Autodiscover\">
        <Request>
            <Domain>~a</Domain>
        </Request>
        </GetFederationInformationRequestMessage>
    </soap:Body>
    </soap:Envelope>" domain))




(defun make-mdi-request (domain)
  (let* ((body (make-mdi-body domain))
         (headers '(("Content-type" . "text/xml; charset=utf-8")
                    ("User-agent" . "AutodiscoverClient")))
         (resp (dex:post "https://autodiscover-s.outlook.com/autodiscover/autodiscover.svc" :headers headers :content body)))
    resp))


(defun parse-mdi-resp (resp)
  (loop for domain in

                   (cdr
                    (xmls:node->nodelist
                     (xmls:xmlrep-find-child-tag "Domains"
                                                 (xmls:xmlrep-find-child-tag "response"
                                                                             (xmls:xmlrep-find-child-tag "getfederationinformationresponsemessage"

                                                                                                         (xmls:xmlrep-find-child-tag "Body" (xmls:parse resp)))))))
        if domain collect (nth 2 domain)))
(defun check-mdi (domain)
  (remove-duplicates (parse-mdi-resp  (make-mdi-request domain)) :test #'string=))



(defun check-mdi* (domain)
  (nhooks:run-hook *check-mdi-setup-hook*)
  (let ((records
          (loop for domain in (check-mdi domain)
                for record = (make-instance 'domain :id (format nil "~a" (sxhash domain)) :dtype "domain" :record domain :tags (list "domain" "cert.sh"))
                do (if (str:containsp "onmicrosoft.com" domain) (push "azure-tenet" (doc-tags record)))
                do (nhooks:run-hook *domain-hook* record)
                collect record)))
    (nhooks:run-hook *check-mdi-finish-hook* records)
    records))
