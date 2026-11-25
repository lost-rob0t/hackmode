(in-package :hackmode-provider-zap)

;;;; Registration of the Star-Lang-declared ZAP tool backends.
;;;;
;;;; One declared tool = one capability/provider pair, matching the MCP
;;;; dispatch table:
;;;;   zap                  -> :web-vuln-scan  zap
;;;;   zap-race-probe       -> :race-probe       zap-race-probe
;;;;   ... and so on for the novel probe family.
;;;;
;;;; Every ZAP backend runs against the operator's daemon and persists its
;;;; typed findings through the canonical provider completion path, so the
;;;; capability, input/output typing, and evidence ownership stay with
;;;; Hackmode — the daemon is a backend, not a second authority.

(defparameter *zap-provider-definitions*
  '(((:web-vuln-scan "zap")
     :handler run-zap-scan*
     :input-type hackmode:url
     :output-types (hackmode:finding)
     :options-p t)
    ((:race-probe "zap-race-probe")
     :handler run-race-probe
     :input-type hackmode:url
     :output-types (hackmode:finding)
     :options-p t)
    ((:smuggle-probe "zap-smuggle-probe")
     :handler run-smuggle-probe
     :input-type hackmode:url
     :output-types (hackmode:finding)
     :options-p t)
    ((:jwt-toolkit "zap-jwt-toolkit")
     :handler run-jwt-toolkit
     :input-type hackmode:url
     :output-types (hackmode:finding)
     :options-p t)
    ((:param-miner "zap-param-miner")
     :handler run-param-miner
     :input-type hackmode:url
     :output-types (hackmode:finding)
     :options-p t)
    ((:authz-diff "zap-authz-diff")
     :handler run-authz-diff
     :input-type hackmode:url
     :output-types (hackmode:finding)
     :options-p t)
    ((:content-discovery "zap-content-discovery")
     :handler run-content-discovery
     :input-type hackmode:url
     :output-types (hackmode:finding)
     :options-p t)
    ((:graphql-probe "zap-graphql-probe")
     :handler run-graphql-probe
     :input-type hackmode:url
     :output-types (hackmode:finding)
     :options-p t))
  "Capability/provider pairs registered for the ZAP daemon backends.")

(defun run-zap-scan* (target options)
  "Options-accepting wrapper around RUN-ZAP-SCAN for registration."
  (run-zap-scan target options :client #'zap-get))

(defun register-zap-providers ()
  "Register the ZAP daemon backends for the declared tools.

Re-registering resets the registrations to the default runners (overwrite by
capability/provider key, like the sibling provider systems). Returns the
registered (capability provider) pairs."
  (let ((registered '()))
    (dolist (entry *zap-provider-definitions*)
      (destructuring-bind ((capability provider) &key handler input-type output-types options-p) entry
        (apply #'hackmode:register-capability-provider
               capability provider (symbol-function handler)
               :input-type input-type
               :output-types output-types
               (when options-p (list :options-p t)))
        (push (list capability provider) registered)))
    (nreverse registered)))
