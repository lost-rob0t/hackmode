(in-package :recon-dns)

;; Provider wrappers remain callable as plain Lisp functions; typed persistence
;; is handled by RECORD-RECON-ASSET instead of ad-hoc IDs/hooks.

(defun subfinder (&rest args)
  "Run subfinder and return its raw stdout."
  (nth 0 (apply #'make-command "subfinder" "-silent" args)))

(defvar *subfinder-setup-hook*
  (make-instance 'nhooks:hook-void :handlers nil)
  "Hook called before subfinder runs.")

(defvar *subfinder-finish-hook*
  (make-instance 'nhooks:hook-void :handlers nil)
  "Hook called after subfinder finishes.")

(defvar *oam-subs-setup-hook*
  (make-instance 'nhooks:hook-void :handlers nil)
  "Hook called before oam-subs runs.")

(defvar *oam-subs-finish-hook*
  (make-instance 'nhooks:hook-any :handlers nil)
  "Hook called with the list of domain objects after oam-subs finishes.")

(defun subfinder* (&rest args)
  "Run subfinder and route discovered domains through Hackmode asset lifecycle."
  (nhooks:run-hook *subfinder-setup-hook*)
  (let* ((output (uiop:split-string (apply #'subfinder args) :separator "\n"))
         (docs
           (loop for name in output
                 unless (string= name "")
                   collect
                   (multiple-value-bind (stored created-p persisted-p)
                       (record-recon-asset
                        (make-instance 'domain
                                       :tags '("dns" "subfinder")
                                       :tool "subfinder"
                                       :dtype "domain"
                                       :record name))
                     (declare (ignore created-p persisted-p))
                     stored))))
    (nhooks:run-hook *subfinder-finish-hook*)
    docs))

(defun oam-subs (&rest args)
  (uiop:split-string
   (nth 0
        (shellpool:run
         (apply #'make-command "oam_subs" "-o /dev/stdout -names" args)))
   :separator "\n"))

;; TODO fix gopath and test the external binary itself.
(defun oam-subs* (&rest args)
  (nhooks:run-hook *oam-subs-setup-hook*)
  (let* ((output (apply #'oam-subs args))
         (domains
           (loop for name in output
                 unless (string= name "")
                   collect
                   (multiple-value-bind (stored created-p persisted-p)
                       (record-recon-asset
                        (make-instance 'domain
                                       :tags '("dns" "oam-subs")
                                       :tool "oam-subs"
                                       :dtype "domain"
                                       :record name))
                     (declare (ignore created-p persisted-p))
                     stored))))
    (nhooks:run-hook *oam-subs-finish-hook* domains)
    domains))

(defun dnsrecon (&rest args)
  (nth 0 (apply #'make-command "dnsrecon" args)))
