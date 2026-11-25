(in-package :hackmode-provider-zap)

;;;; Novel ZAP probe backends: one handler per Star-Lang-declared tool.
;;;;
;;;; Each probe runs its GraalJS plugin inside the daemon (see scripts.lisp)
;;;; and returns ONE typed finding whose data is the plugin result's exact
;;;; JSON — the full verdict, timings, and raw evidence survive verbatim.
;;;; The base URL of the typed input is merged into the plugin params as
;;;; "url"/"baseUrl" so callers only need the raw request payloads in the
;;;; option map.

(defun plugin-params (target options)
  "Merge the typed TARGET's canonical URL into the caller OPTIONS object.
Caller JSON keys win over the injected defaults."
  (labels ((set-key (object key value)
             (cons :obj
                   (cons (cons key value)
                         (remove key (cdr object) :key #'car :test #'string=)))))
    (let* ((base (hackmode:asset-canonical-value target))
           (with-url (if (jsown:keyp options "url")
                         options
                         (set-key options "url" base))))
      with-url)))

(defun zap-plugin-finding (target tool-name plugin-name result)
  "One typed finding for a finished plugin RESULT (exact JSON preserved)."
  (finding-asset target
                 (format nil "zap-~a" plugin-name)
                 (jsown:to-json result)
                 tool-name
                 (list "vuln" "zap" plugin-name)))

(defun run-zap-plugin-probe (target tool-name plugin-name options
                             &key (plugin-runner #'run-zap-plugin))
  "Run PLUGIN-NAME for the declared TOOL-NAME against typed URL TARGET.

OPTIONS is the caller's jsown object (verbatim plugin params) or a plist for
direct Lisp callers. Returns a list with one typed finding carrying the
plugin result's exact JSON."
  (check-type target hackmode:url)
  (hackmode:normalize-asset target)
  (let* ((params (plugin-params target (json-object options)))
         (result (funcall plugin-runner plugin-name params)))
    (list (zap-plugin-finding target tool-name plugin-name result))))

;;; Per-tool handlers; one declared tool = one capability = one handler.

(defun run-race-probe (target options &key (plugin-runner #'run-zap-plugin))
  (run-zap-plugin-probe target "zap-race-probe" "race-probe" options
                        :plugin-runner plugin-runner))

(defun run-smuggle-probe (target options &key (plugin-runner #'run-zap-plugin))
  (run-zap-plugin-probe target "zap-smuggle-probe" "smuggle-probe" options
                        :plugin-runner plugin-runner))

(defun run-jwt-toolkit (target options &key (plugin-runner #'run-zap-plugin))
  (run-zap-plugin-probe target "zap-jwt-toolkit" "jwt-toolkit" options
                        :plugin-runner plugin-runner))

(defun run-param-miner (target options &key (plugin-runner #'run-zap-plugin))
  (run-zap-plugin-probe target "zap-param-miner" "param-miner" options
                        :plugin-runner plugin-runner))

(defun run-authz-diff (target options &key (plugin-runner #'run-zap-plugin))
  (run-zap-plugin-probe target "zap-authz-diff" "authz-diff" options
                        :plugin-runner plugin-runner))

(defun run-content-discovery (target options &key (plugin-runner #'run-zap-plugin))
  (run-zap-plugin-probe target "zap-content-discovery" "content-discovery" options
                        :plugin-runner plugin-runner))

(defun run-graphql-probe (target options &key (plugin-runner #'run-zap-plugin))
  (run-zap-plugin-probe target "zap-graphql-probe" "graphql-probe" options
                        :plugin-runner plugin-runner))

(defun zap-scan-findings (target options &key (client #'zap-get))
  "Backend for the declared \"zap\" tool: bounded spider + active scan +
verbatim alert harvest (see scanner.lisp)."
  (run-zap-scan target options :client client))
