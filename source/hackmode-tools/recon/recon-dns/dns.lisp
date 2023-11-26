(in-package :recon-dns)

;; TODO wrape up shell tool creation into a macro since its just calling it from the shell

(defun subfinder (&rest args)
  "run subfinder"
  (nth 0 (apply #'make-command "subfinder" "-silent" args)))

(defvar *subfinder-setup-hook* (make-instance 'nhooks:hook-void
                                              :handlers nil)
  "Hook That is called before subfinder is ran.")

(defvar *subfinder-finish-hook* (make-instance 'nhooks:hook-void
                                               :handlers nil)
  "Hook That is called after subfinder is finished.")

(defvar *oam-subs-setup-hook* (make-instance 'nhooks:hook-void
                                             :handlers nil)
  "Hook That is called before oam-subs is ran.")

(defvar *oam-subs-finish-hook* (make-instance 'nhooks:hook-void
                                              :handlers nil)
  "Hook That is called after oam-subs is finished.")





(defun subfinder* (&rest args)
  "run subfinder and save output to database"
  (nhooks:run-hook *subfinder-setup-hook*)
  (let* ((output (uiop:split-string (apply #'subfinder args) :separator "\n"))
         (docs (loop for domain in output
                     for record = (make-instance 'domain :id (format nil "~a" (sxhash domain)) :tags '("dns" "subfinder") :dtype "domain" :record domain)
                     do (nhooks:run-hook *domain-hook* record)
                     collect record)))

    (nhooks:run-hook *subfinder-finish-hook*)
    docs))



(defun oam-subs (&rest args)
  (uiop:split-string  (nth 0 (shellpool:run (apply #'make-command "oam_subs" "-o /dev/stdout -names" args))) :separator "\n"))

;; TODO fix gopath and test this
(defun oam-subs* (&rest args)
  (nhooks:run-hook *oam-subs-setup-hook*)
  (let* ((output (apply 'oam-subs args))
         (domains
           (loop for domain in output
                 for record = (make-instance 'domain :id (format nil "~a" (sxhash domain)) :tags '("dns" "oam-subs") :dtype "domain" :record domain)
                 do (nhooks:run-hook *domain-hook* record))))
    (nhooks:run-hook *oam-subs-finish-hook* domains)
    domains))



(defun dnsrecon (&rest args)
  (nth 0  (apply #'make-command "dnsrecon" args)))
