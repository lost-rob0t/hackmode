(uiop:define-package :hackmode

  (:import-from :serapeum :dict :@)
  (:documentation "Core hackmode internalls.")
  (:export
   :EXPLOIT-OPTION-DOCUMENTATION
   :EXPLOIT-NAME
   :USE
   :EXPLOIT-OPTIONS
   :EXPLOIT-OPTION-NAME
   :EXPLOIT-SETUP
   :UNIX-NOW
   :RUN-EXPLOIT
   :EXPLOIT-FUNC
   :EXPLOIT-HELP
   :EXPLOIT-PLATFORM
   :EXPLOIT-OPTION-TYPE
   :hackmode-init-file
   :hackmode-operations-database
   :RHOST
   :payloads
   :config-dir
   :wordlist-dir
   :wordlist-alist
   :wordlist
   :target-platform
   :socks5-proxy-list
   :http-proxy-list
   :exploits-dir
   :history-path
   :prompt
   :*startup-hook*
   :init-database
   :put-doc
   :put-docs
   :*db*
   :*operations-database*
   :meta
   :output
   :host
   :port
   :finding
   :url
   :*api-common-patterns*
   :find-api
   :find-apis
   :*exploits*
   :*current-exploit*
   :exploit-option
   :exploit
   :operation
   :operation-dir
   :domain
   :domain-name
   :domain-type
   :doman-zone))


(in-package :hackmode)
(setq *check-argument-types-explicitly?* t)
