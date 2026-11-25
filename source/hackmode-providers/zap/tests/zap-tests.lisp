(defpackage :hackmode-provider-zap-tests
  (:use :cl)
  (:export :run-tests))

(in-package :hackmode-provider-zap-tests)

(defun assert-equal (expected actual &optional (label "values"))
  (assert (equal expected actual) ()
          "Expected ~a to be ~s, got ~s" label expected actual))

(defun jsval (object key)
  (jsown:val object key))

(defun make-url (value)
  (hackmode:parse-url value))

;;; ---------------------------------------------------------------------
;;; Fake daemon client: records every call and answers canned responses.

(defun make-fake-client ()
  "Return (values client calls) where CALLS is a closure over the recorded
(path-and-query) list."
  (let ((calls '()))
    (values
     (lambda (path-and-query)
       (push path-and-query calls)
       (cond
         ((search "/JSON/spider/action/scan/" path-and-query)
          (jsown:parse "{\"scan\":\"7\"}"))
         ((search "/JSON/spider/view/status/" path-and-query)
          (jsown:parse "{\"status\":\"100\"}"))
         ((search "/JSON/ascan/action/scan/" path-and-query)
          (jsown:parse "{\"scan\":\"9\"}"))
         ((search "/JSON/ascan/view/status/" path-and-query)
          (jsown:parse "{\"status\":\"100\"}"))
         ((search "/JSON/core/view/alerts/" path-and-query)
          (if (search "start=0" path-and-query)
              (jsown:parse (concatenate 'string
                                        "{\"alerts\":[{\"id\":\"1\",\"name\":\"XSS\",\"risk\":\"3\","
                                        "\"url\":\"http://t/x\",\"evidence\":\"<b>\"}]}"))
              (jsown:parse "{\"alerts\":[]}")))
         ((search "/JSON/script/action/runStandAloneScript/" path-and-query)
          (jsown:parse "{\"Result\":\"OK\"}"))
         ((search "/JSON/script/view/globalVar/" path-and-query)
          (jsown:parse
           "{\"globalVar\":\"{\\\"ok\\\":true,\\\"verdict\\\":\\\"uniform\\\"}\"}"))
         (t (jsown:parse "{\"Result\":\"OK\"}"))))
     (lambda () (nreverse calls)))))

(defun make-stuck-client ()
  "Status views never reach 100, so every phase hits its deadline."
  (lambda (path-and-query)
    (cond
      ((search "/JSON/spider/action/scan/" path-and-query)
       (jsown:parse "{\"scan\":\"7\"}"))
      ((search "/JSON/spider/view/status/" path-and-query)
       (jsown:parse "{\"status\":\"50\"}"))
      ((search "/JSON/ascan/action/scan/" path-and-query)
       (jsown:parse "{\"scan\":\"9\"}"))
      ((search "/JSON/ascan/view/status/" path-and-query)
       (jsown:parse "{\"status\":\"50\"}"))
      ((search "/JSON/core/view/alerts/" path-and-query)
       (jsown:parse "{\"alerts\":[]}"))
      (t (jsown:parse "{\"Result\":\"OK\"}")))))

(defun make-plugin-runner (result)
  "A plugin runner double that returns RESULT regardless of input and
records the plugin name and params it saw."
  (let ((seen nil))
    (values
     (lambda (name params)
       (push (list name params) seen)
       result)
     (lambda () (nreverse seen)))))

;;; ---------------------------------------------------------------------
;;; Tests

(defun run-percent-encode-test ()
  (assert-equal "plain" (hackmode-provider-zap:percent-encode "plain"))
  (assert-equal "a%20b" (hackmode-provider-zap:percent-encode "a b"))
  (assert-equal "GET%20%2Fx%20HTTP%2F1.1%0A"
                (hackmode-provider-zap:percent-encode "GET /x HTTP/1.1
"))
  (assert-equal "unreserved-._~still"
                (hackmode-provider-zap:percent-encode "unreserved-._~still"))
  (assert-equal "%C3%A9" (hackmode-provider-zap:percent-encode "é")))

(defun run-error-shape-test ()
  ;; A daemon API error raises ZAP-ERROR carrying the complete body.
  (assert (eq (hackmode-provider-zap:zap-error-body
               (make-condition 'hackmode-provider-zap:zap-error
                               :message "m" :body "the body"))
              "the body")))

(defun run-plugin-runner-test ()
  ;; The runner follows the global-var round-trip in order and parses the
  ;; plugin's JSON result.
  (multiple-value-bind (client calls) (make-fake-client)
    (let ((result (hackmode-provider-zap:run-zap-plugin
                   "race-probe" '(:count 8) :client client)))
      (assert-equal t (jsval result "ok"))
      (let ((recorded (funcall calls)))
        ;; setGlobalVar(result clear), setGlobalVar(params), remove (stateless
        ;; refresh), load, runStandAloneScript, globalVar
        (assert (search "/JSON/script/action/setGlobalVar/?varKey=zmcp.result"
                        (first recorded))
                ()
                "result var is cleared first")
        (assert (search "/JSON/script/action/setGlobalVar/?varKey=zmcp.params"
                        (second recorded))
                ()
                "params var is set second")
        (assert (search "/JSON/script/action/remove/" (third recorded))
                () "script is removed before load (load refuses overwrite)")
        (assert (search "/JSON/script/action/load/" (fourth recorded)))
        (assert (search "scriptName=race-probe" (fourth recorded)))
        (assert (search "/JSON/script/action/runStandAloneScript/"
                        (fifth recorded)))
        (assert (search "/JSON/script/view/globalVar/?varKey=zmcp.result"
                        (sixth recorded)))))
    ;; plist options encode with lowercase string keys.
    (multiple-value-bind (client2 calls2) (make-fake-client)
      (hackmode-provider-zap:run-zap-plugin
       "jwt-toolkit" '(:mode analyze :token "a.b") :client client2)
      (let ((params-call (find "zmcp.params" (funcall calls2)
                               :test #'search)))
        (assert params-call ()
                "plugin params var was set")))))

(defun run-plugin-missing-test ()
  (assert (not (null (hackmode-provider-zap:zap-plugin-names))))
  (dolist (name (hackmode-provider-zap:zap-plugin-names))
    (assert (probe-file (hackmode-provider-zap:zap-plugin-pathname name))
            ()
            "plugin script ~a ships with the system" name)))

(defun run-probe-test ()
  ;; A probe turns the plugin result into exactly one finding whose data is
  ;; the result's exact JSON, and the typed input's URL is injected.
  (multiple-value-bind (runner seen) (make-plugin-runner
                                      (jsown:parse
                                       "{\"ok\":true,\"verdict\":\"uniform\"}"))
    (let ((findings (hackmode-provider-zap:run-race-probe
                     (make-url "http://target.example/app")
                     (jsown:parse "{\"count\":16}")
                     :plugin-runner runner)))
      (assert-equal 1 (length findings))
      (let ((finding (first findings)))
        (assert-equal "zap-race-probe" (hackmode:finding-finding-type finding))
        (assert-equal "zap-race-probe" (hackmode:doc-tool finding))
        (assert-equal "{\"ok\":true,\"verdict\":\"uniform\"}"
                      (hackmode:finding-data finding)
                      "plugin result JSON preserved verbatim"))
      (let ((entry (first (funcall seen))))
        (assert-equal "race-probe" (first entry))
        (assert-equal "http://target.example/app"
                      (jsval (second entry) "url")
                      "typed input URL injected into plugin params")
        (assert-equal 16 (jsval (second entry) "count")
                      "caller options pass through verbatim")))))

(defun run-probe-options-precedence-test ()
  ;; Caller-supplied url wins over the injected canonical URL.
  (multiple-value-bind (runner seen)
      (make-plugin-runner (jsown:parse "{\"ok\":true}"))
    (let ((_ (hackmode-provider-zap:run-smuggle-probe
              (make-url "http://target.example/app")
              (jsown:parse "{\"url\":\"http://caller.example/\"}")
              :plugin-runner runner))
          (entry (first (funcall seen))))
      (declare (ignore _))
      (assert-equal "http://caller.example/"
                    (jsval (second entry) "url")
                    "caller url key wins over injected url"))))

(defun run-scan-test ()
  ;; Full flow: spider, active scan, verbatim alert harvest, findings.
  (multiple-value-bind (client calls) (make-fake-client)
    (let ((findings (hackmode-provider-zap:zap-scan-findings
                     (make-url "http://target.example/")
                     '(:max-children 12 :spider-minutes 1 :scan-minutes 1)
                     :client client)))
      (assert-equal 1 (length findings))
      (let ((finding (first findings)))
        (assert-equal "zap-alert" (hackmode:finding-finding-type finding))
        (assert-equal "zap" (hackmode:doc-tool finding))
        (assert (search "\"name\":\"XSS\"" (hackmode:finding-data finding))
                () "alert evidence preserved verbatim")
        (assert (member "risk-3" (hackmode:doc-tags finding) :test #'string=)))
      (let ((recorded (funcall calls)))
        (assert (some (lambda (call) (search "/JSON/spider/action/scan/" call))
                      recorded))
        (assert (some (lambda (call) (search "maxChildren=12" call)) recorded)
                () "caller maxChildren reaches the daemon")
        (assert (some (lambda (call) (search "/JSON/ascan/action/scan/" call))
                      recorded))
        (assert (some (lambda (call) (search "/JSON/core/view/alerts/" call))
                      recorded))))))

(defun run-scan-deadline-test ()
  ;; A stuck scan stops through the daemon and records the cut as a note.
  ;; Short deadlines + fast polls keep the test wall-clock tiny.
  (let ((hackmode-provider-zap:*zap-scan-poll-seconds* 0.05))
    (let ((findings (hackmode-provider-zap:zap-scan-findings
                     (make-url "http://target.example/")
                     '(:spider-minutes 0.05 :scan-minutes 0.05)
                     :client (make-stuck-client))))
      (let ((notes (remove-if-not
                    (lambda (f)
                      (string= "zap-scan-note"
                               (hackmode:finding-finding-type f)))
                    findings)))
        (assert-equal 2 (length notes)
                      "spider and scan deadline cuts recorded")
        (dolist (note notes)
          (assert (search "\"deadlineReached\":true"
                          (hackmode:finding-data note))
                  () "deadline notes are truthful"))))))

(defun run-options-threading-test ()
  ;; Options-p providers receive the option map; unary providers do not.
  (let ((seen '()))
    (hackmode:register-capability-provider
     :threading-test "options"
     (lambda (input options)
       (declare (ignore input))
       (push options seen)
       nil)
     :input-type 'hackmode:url
     :options-p t)
    (hackmode:register-capability-provider
     :threading-test "unary"
     (lambda (input)
       (declare (ignore input))
       (push :unary seen)
       nil)
     :input-type 'hackmode:url)
    (hackmode:run-capability :threading-test (make-url "http://t.example/")
                             :provider "options"
                             :options (jsown:parse "{\"count\":16}")
                             :database nil)
    (assert (and (= 1 (length seen))
                 (equal 16 (jsown:val (first seen) "count")))
            ()
            "options-p handler received the option map")
    (setf seen '())
    (hackmode:run-capability :threading-test (make-url "http://t.example/")
                             :provider "unary"
                             :options (jsown:parse "{\"count\":16}")
                             :database nil)
    (assert-equal '(:unary) seen "unary handler contract unchanged")))

(defun run-registration-test ()
  ;; All declared zap tool backends register with URL input typing.
  (let ((registered (hackmode-provider-zap:register-zap-providers)))
    (assert-equal 8 (length registered))
    (dolist (pair registered)
      (let ((definition (hackmode:find-capability-provider
                         (first pair) (second pair))))
        (assert definition ()
                "provider ~a/~a registered" (first pair) (second pair))
        (assert (eq 'hackmode:url
                    (hackmode:capability-provider-input-type definition))
                ()
                "~a takes typed url input" (second pair))
        (assert (hackmode:capability-provider-options-p definition)
                ()
                "~a accepts options" (second pair))))))

(defun run-tests ()
  (run-percent-encode-test)
  (run-error-shape-test)
  (run-plugin-missing-test)
  (run-plugin-runner-test)
  (run-probe-test)
  (run-probe-options-precedence-test)
  (run-scan-test)
  (run-scan-deadline-test)
  (run-options-threading-test)
  (run-registration-test)
  (format t "Hackmode ZAP provider tests passed.~%")
  t)
