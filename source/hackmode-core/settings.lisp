;;;; User-facing Hackmode configuration.
(in-package :hackmode)

(defvar config-dir
  (nfiles:expand (make-instance 'nfiles:config-file :base-path #p"hackmode/"))
  "Path to user configuration.")

(defvar hackmode-init-file
  (nfiles:expand
   (make-instance 'nfiles:config-file
                  :base-path (uiop:merge-pathnames* config-dir #p"init.lisp")))
  "Path to the Hackmode init file. Defaults to ~/.config/hackmode/init.lisp.")

(defvar data-dir
  (nfiles:expand (make-instance 'nfiles:data-file :base-path #p"hackmode/"))
  "Local Hackmode data path. Defaults to ~/.local/share/hackmode.")

(defvar hackmode-operations-database
  (nfiles:expand
   (make-instance 'nfiles:data-file
                  :base-path (uiop:merge-pathnames* ".db/" data-dir)))
  "Path to the database that maintains operation workspace records.")

(defvar RHOST nil "Target host address for a payload.")
(defvar LHOST nil "Local listen address for a payload.")
(defvar payloads nil "List of payloads.")

(defvar wordlist-dir
  (nfiles:expand
   (make-instance 'nfiles:data-file
                  :base-path (uiop:merge-pathnames* "wordlists/" data-dir)))
  "User wordlist directory.")

(defvar wordlist-alist nil "Alist of tasks/tools to default wordlists.")
(defvar wordlist nil "Current wordlist; has highest priority.")
(defvar target-platform nil "Current target platform operating system.")

(defvar socks5-proxy-list nil
  "SOCKS5 proxy addresses in socks5://ip:port form.")
(defvar http-proxy-list nil
  "HTTP proxy addresses in http://ip:port form.")

(defvar exploits-dir
  (nfiles:expand
   (make-instance 'nfiles:data-file
                  :base-path (uiop:merge-pathnames* "exploits/" data-dir)))
  "Path to the exploit directory.")

(defvar exploits-dependency-dir
  (nfiles:expand
   (make-instance 'nfiles:data-file
                  :base-path (uiop:merge-pathnames* "exploits/" data-dir)))
  "Path to exploit dependencies.")

(defvar history-dir
  (nfiles:expand
   (make-instance 'nfiles:data-file
                  :base-path (uiop:merge-pathnames* data-dir "history.lisp")))
  "History file path.")

(defvar prompt "HACK$> " "Prompt used for interactive command input.")

(defvar dependency-dir
  (nfiles:expand
   (make-instance 'nfiles:data-file
                  :base-path (uiop:merge-pathnames* "deps/" data-dir)))
  "Path where tool dependencies are downloaded.")

;; Hook contracts matter: HOOK-VOID is only for callbacks that take no
;; arguments. Finding/domain handlers receive the discovered object, so these
;; must be HOOK-ANY.
(defvar *startup-hook*
  (make-instance 'nhooks:hook-void :handlers nil)
  "Hook run when Hackmode starts. Handlers take no arguments.")

(defvar *finding-hook*
  (make-instance 'nhooks:hook-any :handlers nil)
  "Compatibility hook run with a discovered finding object.")

(defvar *domain-hook*
  (make-instance 'nhooks:hook-any :handlers nil)
  "Compatibility hook run with a discovered domain object.")

(defvar *interactive* nil "Whether Hackmode is running from a REPL/shell.")
