(in-package :recon-dns)



;; TODO wrape up shell tool creation into a macro since its just calling it from the shell


(defun make-command (command &rest args)
  (let* ((stream (make-string-output-stream))
         (*standard-output* stream)
         (code (shellpool:run (format nil "~a ~{~a~^ ~}" command args))))
    (list (get-output-stream-string stream) code)))




(defun subfinder (&rest args)
  "run subfinder"
  (nth 0 (apply #'make-command "subfinder" "-silent" args)))

(defvar *subfinder-setup-hook* (make-instance 'nhooks:hook-void
                                              :handlers nil)
  "Hook That is called before subfinder is ran.")

(defvar *subfinder-finish-hook* (make-instance 'nhooks:hook-void
                                               :handlers nil)
  "Hook That is called after subfinder is finished.")



(defun subfinder* (&rest args)
  "run subfinder and save output to database"
  (nhooks:run-hook *subfinder-setup-hook*)
  (let* ((output (uiop:split-string (apply #'subfinder args) :separator "\n"))
         (docs (loop for domain in output
                     do (format t "~a" domain)
                     collect (make-instance 'domain :id (format nil "~a" (sxhash domain)) :tags '("dns" "subfinder") :dtype "domain" :record domain))))
    (nhooks:run-hook *subfinder-finish-hook*)
    docs))



(defun amass (&rest args)
  (nth 0 (shellpool:run (apply #'make-command "oam_subs" "-o /dev/stdout -names" args))))


(defun amass* (&rest args)
  (let ((output (apply 'amass args)))
    (loop for domain in (uiop:split-string output :separator "\n")
          collect (make-instance 'domain :id (format nil "~a" (sxhash domain)) :tags '("dns" "amass") :dtype "domain" :record domain))))


(defun dnsrecon (&rest args)
  (nth 0  (apply #'make-command "dnsrecon" args)))
