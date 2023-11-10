;;;;  This file is ment to be a user facing config options that is ment to be changed,
;;;;  although everything can be, just these are explitit options

(in-package :hackmode)

(defvar hackmode-init-file (nfiles:expand (make-instance 'nfiles:config-file :base-path #p"hackmode/init.lisp")) "The path to the init file for hackmode")

(defvar RHOST nil "The target host address for a payload")
(defvar LHOST nil "The target Listen Address for payload")
(defvar payloads nil "A List of payloads.")
(defvar config-dir nil "A Path to user configuration")
(defvar wordlist-dir (uiop:parse-native-namestring "~/wordlists/") "The Path to user directory of wordlists")
(defvar wordlist-alist nil "An Alist of tasks/tools to default wordlists to be used.")
(defvar wordlist nil "The current wordlist to use, it has the highest priority")
(defvar target-platform nil "The target platform Operating system.")

;; NOTE Platforms are represented as a symbol

;; TODO Find a use case
(defvar socks5-proxy-list nil "List of socks5 proxy addresses. Must be in the format of socks5://ip:port")
(defvar http-proxy-list nil "List of http proxy addresses. Must be in the format of http://ip:port")
(defvar exploits-dir () "Path to exploit dir where exploits are stored.")

(defvar history-path (nfiles:expand (make-instance 'nfiles:data-file :base-path #p"hackmode/history.lisp")))



;; Ricing related
(defvar prompt "HACK$> " "The prompt to be used for command inputs.")
