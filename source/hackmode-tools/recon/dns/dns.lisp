(uiop:define-package   :recon.dns
  (:use :cl)
  (:documentation "DNS recon tooling"))

(in-package :dns-recon)

(shellpool:start)

;; TODO wrape up shell tool creation into a macro since its just calling it from the shell
(defvar subfinder-path (shellpool:run "which subfinder"))


(defun make-command (command &rest args)
  "Run a program with a list of options using uiop:run-program."
  (format t "~a ~{~a~^ ~}" command args))


(defun subfinder (&rest args)
  (shellpool:run (apply #'make-command "subfinder" args)))

(defvar amass-path (shellpool:run "which amass"))
(defun amass (&rest args)
  (shellpool:run (apply #'make-command "amass" args)))

(defvar dnsrecon-path (shellpool:run "which dnsrecon"))
(defun dnsrecon (&rest args)
  (shellpool:run (apply #'make-command "dnsrecon" args)))


(defvar dnsrecon-path (shellpool:run "which dnsrecon"))
(defun dnsrecon (&rest args)
  (shellpool:run (apply #'make-command "dnsrecon" args)))



