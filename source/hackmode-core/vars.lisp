(in-package :hackmode)

(defvar* (*current-exploit* exploit) (make-instance 'exploit :name "Hackmode" :platform "hackmode") "The Current package to be ran. this may be a exploit, a tool, ect.")
(defvar* (*exploits* hash-table) (dict) "The current list of loaded exploits in hackmode.")
(defvar* (*history* list)  "The history object.")
(defvar* (*last-command*  string) "" "The last command that was ran.")
