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
   :EXPLOIT-OPTION-TYPE))


(in-package :hackmode)
(setq *check-argument-types-explicitly?* t)
