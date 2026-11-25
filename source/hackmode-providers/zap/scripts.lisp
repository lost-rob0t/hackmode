(in-package :hackmode-provider-zap)

;;;; Novel ZAP plugin runner.
;;;;
;;;; The novel capability plugins are GraalJS standalone scripts executed
;;;; inside the daemon through the script add-on's own API — the same
;;;; mechanism ZAP's script console uses, so nothing here adds a second
;;;; script runtime:
;;;;   1. setGlobalVar(zmcp.params)  — JSON params in
;;;;   2. script/load                — register/refresh the script from disk
;;;;   3. script/runStandAloneScript — runs synchronously
;;;;   4. script/globalVar(zmcp.result) — JSON result out
;;;; Scripts live under zap-scripts/ and are ASDF static files of this
;;;; system; the provider owns their content.

(defparameter *script-engine* "ECMAScript : Graal.js")
(defparameter *params-var* "zmcp.params")
(defparameter *result-var* "zmcp.result")

(defun zap-plugin-pathname (name)
  "Absolute pathname of plugin script NAME (a file stem) in this system."
  (asdf:system-relative-pathname :hackmode-provider-zap
                                 (format nil "zap-scripts/~a.js" name)))

(defun zap-plugin-names ()
  "The plugin scripts shipped by this provider system."
  '("race-probe" "smuggle-probe" "jwt-toolkit" "param-miner"
    "authz-diff" "content-discovery" "graphql-probe"))

(defun ignore-zap-daemon-error (form)
  "Run FORM, swallowing ZAP-ERROR (used for idempotent refresh calls:
removing a plugin script that is not registered is fine)."
  (handler-case form
    (zap-error () nil)))

(defun run-zap-plugin (name options &key (client #'zap-get))
  "Run plugin NAME with an OPTIONS plist; return the parsed result plist.

The plugin contract is the global-var round-trip: params arrive as the JSON
of OPTIONS (string keys), the plugin stores its JSON result in the result
var. The script is re-registered on every run (remove then load — the
daemon's load refuses to overwrite an existing script, and content edits
must land without a daemon restart). A missing or non-JSON result is an
error carrying everything the daemon returned, never a silent nil. CLIENT
is injectable for tests."
  (let ((file (namestring (zap-plugin-pathname name))))
    (unless (probe-file file)
      (error "ZAP plugin script ~a is missing at ~a." name file))
    (zap-call-with client "script" "action" "setGlobalVar"
                   "varKey" *result-var* "varValue" "")
    (zap-call-with client "script" "action" "setGlobalVar"
                   "varKey" *params-var*
                   "varValue" (jsown:to-json (json-object options)))
    ;; Refresh registration: remove swallows the does-not-exist case, load
    ;; then registers the current file content.
    (ignore-zap-daemon-error
      (zap-call-with client "script" "action" "remove" "scriptName" name))
    (zap-call-with client "script" "action" "load"
                   "scriptName" name
                   "scriptType" "standalone"
                   "scriptEngine" *script-engine*
                   "fileName" file
                   "charset" "UTF-8")
    (zap-call-with client "script" "action" "runStandAloneScript"
                   "scriptName" name)
    (let ((response (zap-call-with client "script" "view" "globalVar"
                                   "varKey" *result-var*)))
      (unless (jsown:keyp response "globalVar")
        (error 'zap-error
               :message (format nil "ZAP plugin ~a produced no result var." name)))
      (let ((text (jsown:val response "globalVar")))
        (unless (and (stringp text) (plusp (length text)))
          (error 'zap-error
                 :message (format nil "ZAP plugin ~a left an empty result var." name)))
        (let ((parsed (jsown:parse text)))
          (if (and (jsown:keyp parsed "ok") (jsown:val parsed "ok"))
              parsed
              (error 'zap-error
                     :message (format nil "ZAP plugin ~a failed: ~a"
                                      name
                                      (if (jsown:keyp parsed "error")
                                          (jsown:val parsed "error")
                                          text))
                     :body text)))))))

(defun json-object (options)
  "Normalize OPTIONS to a jsown object: an existing :obj passes through
verbatim (the MCP layer forwards caller JSON untouched); a plist is converted
with lowercase string keys."
  (if (and (consp options) (eq (car options) :obj))
      options
      (options-to-json options)))

(defun options-to-json (options)
  "Convert an OPTIONS plist into a jsown object with string keys.

Keyword keys become lowercase strings verbatim (:raw-request -> rawrequest is
wrong; the keyword symbol name minus the colon, lowercased, hyphens preserved:
:raw-request -> raw-request)."
  (flet ((clean (key)
           (let ((text (princ-to-string key)))
             (string-downcase (if (char= (char text 0) #\:)
                                  (subseq text 1)
                                  text)))))
    (cons :obj
          (loop for (key value) on options by #'cddr
                collect (cons (clean key) (json-value value))))))

(defun json-value (value)
  "Adapt one Lisp VALUE to a jsown-encodable value."
  (typecase value
    (string value)
    (integer value)
    (float value)
    (symbol (if (null value) :false (princ-to-string value)))
    (list
     (if (and (consp value) (eq (car value) :obj))
         value
         (let ((plistp (and (consp value) (keywordp (car value)))))
           (if plistp
               (options-to-json value)
               (cons :array (mapcar #'json-value value))))))
    (t (princ-to-string value))))
