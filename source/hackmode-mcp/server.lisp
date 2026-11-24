(in-package :hackmode-mcp)

;;;; Executable entrypoint.
;;;;
;;;; The MCP image deliberately does NOT load ~/.config/hackmode/init.lisp:
;;;; a headless server must not depend on LISH-oriented user init code.
;;;; Startup still runs Hackmode's *startup-hook* so the operations
;;;; registry opens exactly as any other client's would.

(defun main ()
  "Canonical bootstrap, then the stdio server loop."
  (nhooks:run-hook hackmode:*startup-hook*)
  (uiop:quit (run-server)))
