;;;;  This file is ment to be a user facing config options that is ment to be changed,
;;;;  although everything can be, just these are explitit options
(in-package :hackmode)


(defvar config-dir (nfiles:expand (make-instance 'nfiles:config-file :base-path #p"hackmode/")) "A Path to user configuration")

(defvar hackmode-init-file (nfiles:expand (make-instance 'nfiles:config-file :base-path (uiop:merge-pathnames* config-dir #p"init.lisp"))) "The path to the init file for hackmode. Defaults to ~/.config/hackmode/init.lisp")

(defvar data-dir (nfiles:expand (make-instance 'nfiles:data-file :base-path #p"hackmode/")) "The local data path, defaults to ~/.local/share/hackmode")

(defvar hackmode-operations-database (nfiles:expand (make-instance 'nfiles:data-file :base-path (uiop:merge-pathnames* ".db/" data-dir ))) "The Path to database file that maintains paths to operations.")

(defvar RHOST nil "The target host address for a payload")

(defvar LHOST nil "The target Listen Address for payload")

(defvar payloads nil "A List of payloads.")

(defvar wordlist-dir (nfiles:expand (make-instance 'nfiles:data-file :base-path (uiop:merge-pathnames* "wordlists/" data-dir))) "The Path to user directory of wordlists, defaults to data-dir/wordlists/")

(defvar wordlist-alist nil "An Alist of tasks/tools to default wordlists to be used.")

(defvar wordlist nil "The current wordlist to use, it has the highest priority")

(defvar target-platform nil "The target platform Operating system.")

;; NOTE Platforms are represented as a symbol

;; TODO Use a scheme://ip:port proxy system
(defvar socks5-proxy-list nil "List of socks5 proxy addresses. Must be in the format of socks5://ip:port")

(defvar http-proxy-list nil "List of http proxy addresses. Must be in the format of http://ip:port")

(defvar exploits-dir (nfiles:expand (make-instance 'nfiles:data-file :base-path (uiop:merge-pathnames* "exploits/" data-dir))) "Path to exploit dir where exploits are stored.")

(defvar exploits-dependency-dir (nfiles:expand (make-instance 'nfiles:data-file :base-path (uiop:merge-pathnames* "exploits/" data-dir))) "Path to exploit dir where exploit dependencies are stored.")

(defvar history-dir (nfiles:expand (make-instance 'nfiles:data-file :base-path (uiop:merge-pathnames* data-dir "history.lisp"))) "The history File, defaults to data-dir/history.lisp")

;; Ricing related
(defvar prompt "HACK$> " "The prompt to be used for command inputs.")

(defvar dependency-dir (nfiles:expand (make-instance 'nfiles:data-file :base-path (uiop:merge-pathnames* "deps/" data-dir)))
  "The Path for where dependency of tools will be downloaded. ")

;; hackmode internals
(defvar *startup-hook* (make-instance 'nhooks:hook-void
                                      :handlers nil) "Hook That is called when hackmode-user is started.")
(defvar *finding-hook* (make-instance 'nhooks:hook-void
                                      :handlers nil)
  "Hook That is called when a finding is found. Takes the finding object as the argument")

(defvar *domain-hook* (make-instance 'nhooks:hook-void
                                     :handlers nil)
  "Hook That is called when a domain is found. Takes the domain object as the argument")

(defvar *interactive* nil "Is hackmode being run from a repl/shell?")
