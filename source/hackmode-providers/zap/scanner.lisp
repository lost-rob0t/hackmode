(in-package :hackmode-provider-zap)

;;;; Classic ZAP scanner backend for the declared "zap" vuln tool.
;;;;
;;;; Synchronous and bounded: spider, then active scan, then alert harvest,
;;;; each phase under a wall-clock deadline. When a deadline hits, the phase
;;;; is stopped through the daemon's own stop action and a zap-scan-note
;;;; finding records exactly what was cut off — no silent partial scans.
;;;;
;;;; The daemon client is injectable (&key client) so tests double it.

(defparameter *zap-scan-poll-seconds* 2
  "Seconds between daemon progress polls.")

(defparameter *zap-max-children* 50
  "Hard cap on spider maxChildren.")

(defparameter *zap-max-scan-minutes* 15
  "Hard cap on per-phase wall-clock minutes.")

(defun zap-call-with (client component kind name &rest plist)
  "Call the daemon through CLIENT (defaults to the real daemon GET)."
  (funcall client
           (if plist
               (format nil "/JSON/~a/~a/~a/?~a"
                       component kind name (query-string plist))
               (format nil "/JSON/~a/~a/~a/" component kind name))))

(defun clamp-number (value max default)
  (let ((n (and (numberp value) (plusp value) value)))
    (min (or n default) max)))

(defun phase-deadline (minutes)
  (+ (get-universal-time)
     (round (* (clamp-number minutes *zap-max-scan-minutes* 10) 60))))

(defun scan-id-of (response)
  (if (jsown:keyp response "scan")
      (princ-to-string (jsown:val response "scan"))
      (error 'zap-error
             :message "ZAP daemon did not return a scan id."
             :body (jsown:to-json response))))

(defun poll-until (client component view params deadline)
  "Poll the daemon status VIEW until it reports \"100\" or DEADLINE passes.
Returns (values status-or-nil deadline-reached-p)."
  (loop
    with path-args = (append (list component "view" view) params)
    do (let* ((response (apply #'zap-call-with client path-args))
              (status (princ-to-string (jsown:val response "status"))))
         (when (string= status "100")
           (return (values status nil)))
         (when (>= (get-universal-time) deadline)
           (return (values status t))))
    do (sleep *zap-scan-poll-seconds*)))

(defun finding-asset (target type data tool tags)
  "One typed finding asset; DATA is the exact evidence string."
  (make-instance 'hackmode:finding
                 :document-id (hackmode:asset-deterministic-id target)
                 :finding-type type
                 :data data
                 :tool tool
                 :tags tags))

(defun alert-to-json-string (alert)
  "Serialize one daemon alert object back to exact JSON text."
  (jsown:to-json alert))

(defun alerts-to-findings (target alerts &key (tool "zap"))
  "Convert verbatim daemon ALERTS into typed finding assets for TARGET.
One alert becomes one finding whose data is the alert's exact JSON — the
evidence value survives the trip unchanged."
  (mapcar (lambda (alert)
            (finding-asset target "zap-alert" (alert-to-json-string alert) tool
                           (list "vuln" "zap"
                                 (format nil "risk-~a"
                                         (if (jsown:keyp alert "risk")
                                             (jsown:val alert "risk")
                                             "unknown")))))
          alerts))

(defun scan-note-finding (target alist &key (tool "zap"))
  "One typed finding carrying a scan-progress NOTE (deadline cuts)."
  (finding-asset target "zap-scan-note"
                 (jsown:to-json (cons :obj alist)) tool
                 (list "vuln" "zap" "scan-note")))

(defun harvest-alerts (client base-url)
  "Harvest every alert for BASE-URL, paginated to the end (cap 1000).
Returns the raw jsown alert objects, verbatim."
  (let ((alerts '())
        (start 0)
        (page 100))
    (loop
      do (let* ((response (zap-call-with client "core" "view" "alerts"
                                         "baseurl" base-url
                                         "start" (princ-to-string start)
                                         "count" (princ-to-string page)))
                (batch (jsown:val response "alerts")))
           (setf alerts (append alerts batch))
           (if (< (length batch) page)
               (return alerts)
               (setf start (+ start page))))
      while (< start 1000))))

(defun run-zap-scan (target options &key (client #'zap-get))
  "Run the declared zap vuln tool against typed URL TARGET with OPTIONS.

OPTIONS keys (all optional): :max-children (cap 50), :spider-minutes and
:scan-minutes (cap 15 each), :recurse (default t), :mode (:full :spider
:scan, default :full — spider-only or scan-only skip the other phase).

Returns a list of typed finding assets: one zap-alert finding per daemon
alert (exact JSON preserved) plus zap-scan-note findings for any deadline
cuts. Requires a reachable daemon; daemon errors carry the complete response."
  (check-type target hackmode:url)
  (hackmode:normalize-asset target)
  (let* ((base-url (hackmode:asset-canonical-value target))
         (mode (getf options :mode :full))
         (notes '()))
    (unless (find mode '(:full :spider :scan))
      (error "zap scan mode must be :full, :spider or :scan, got ~s." mode))
    (let ((spider-minutes (getf options :spider-minutes 5))
          (scan-minutes (getf options :scan-minutes 10))
          (max-children (clamp-number (getf options :max-children)
                                       *zap-max-children* 10))
          (recurse (if (eq (getf options :recurse) :false) "false" "true")))
      (when (member mode '(:full :spider))
        (let ((deadline (phase-deadline spider-minutes))
              (scan-id (scan-id-of (zap-call-with client "spider" "action" "scan"
                                                  "url" base-url
                                                  "maxChildren"
                                                  (princ-to-string max-children)
                                                  "recurse" recurse))))
          (multiple-value-bind (percent deadline-reached-p)
              (poll-until client "spider" "status"
                          (list "scanId" scan-id) deadline)
            (declare (ignore percent))
            (when deadline-reached-p
              (zap-call-with client "spider" "action" "stop" "scanId" scan-id)
              (push (list (cons "deadlineReached" :true)
                          (cons "phase" "spider")
                          (cons "target" base-url))
                    notes)))))
      (when (member mode '(:full :scan))
        (let ((deadline (phase-deadline scan-minutes))
              (scan-id (progn
                         (zap-call-with client
                                        "ascan" "action"
                                        "setOptionMaxScanDurationInMins"
                                        "Integer"
                                        (princ-to-string
                                         (clamp-number scan-minutes
                                                        *zap-max-scan-minutes* 10)))
                         (scan-id-of (zap-call-with client "ascan" "action" "scan"
                                                    "url" base-url
                                                    "recurse" recurse
                                                    "inScopeOnly" "false"
                                                    "scanPolicyName" ""
                                                    "method" "GET"
                                                    "postData" "")))))
          (multiple-value-bind (percent deadline-reached-p)
              (poll-until client "ascan" "status"
                          (list "scanId" scan-id) deadline)
            (declare (ignore percent))
            (when deadline-reached-p
              (zap-call-with client "ascan" "action" "stop" "scanId" scan-id)
              (push (list (cons "deadlineReached" :true)
                          (cons "phase" "scan")
                          (cons "target" base-url))
                    notes)))))
      (let ((findings (alerts-to-findings target
                                          (harvest-alerts client base-url))))
        (dolist (note notes)
          (push (scan-note-finding target note) findings))
        findings))))
