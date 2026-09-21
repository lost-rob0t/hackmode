(in-package :hackmode-provider-wireless)

;;; airmon-ng monitor-mode management.
;;;
;;; The runner is injectable: every public function takes
;;; &KEY (RUNNER #'SHELL-RUNNER) where the runner is called as
;;;
;;;   (funcall runner program argument-list) => stdout stderr exit-code
;;;
;;; The default SHELL-RUNNER guards on binary presence and shells out through
;;; UIOP:RUNPROGRAM with argv lists (no shell string interpolation). Tests
;;; inject scripted outputs.

(defparameter *airmon-ng-program*
  (or (uiop:getenv "HACKMODE_AIRMON_NG_PROGRAM") "airmon-ng")
  "airmon-ng executable used by the wireless provider.")

(define-condition aircrack-tool-unavailable (error)
  ((program :initarg :program :reader aircrack-tool-unavailable-program))
  (:report (lambda (condition stream)
             (format stream "~a was not found in PATH; install the aircrack-ng suite"
                     (aircrack-tool-unavailable-program condition)))))

(define-condition aircrack-command-failed (error)
  ((program :initarg :program :reader aircrack-command-failed-program)
   (exit-code :initarg :exit-code :reader aircrack-command-failed-exit-code)
   (output :initarg :output :reader aircrack-command-failed-output))
  (:report (lambda (condition stream)
             (format stream "~a exited with status ~a: ~a"
                     (aircrack-command-failed-program condition)
                     (aircrack-command-failed-exit-code condition)
                     (string-trim '(#\Space #\Tab #\Newline #\Return)
                                  (or (aircrack-command-failed-output condition) ""))))))

(defun find-program-in-path (program)
  "Return the absolute path of PROGRAM inside PATH, or NIL."
  (when (and (plusp (length program))
             (not (find #\/ program)))
    (loop with separator = (or (uiop:directory-separator-for-host) #\/)
          for directory in (uiop:split-string (or (uiop:getenv "PATH") "")
                                              :separator (list separator))
          for probe = (merge-pathnames program
                                       (parse-namestring
                                        (concatenate 'string directory "/")))
          when (and (probe-file probe)
                    (uiop:file-pathname-p probe))
            do (return (truename probe))))
  ;; Absolute or relative explicit paths are trusted to PROBE-FILE.
  (when (and (plusp (length program))
             (find #\/ program))
    (let ((probe (probe-file program)))
      (when probe (truename probe)))))

(defun ensure-tool-available (program)
  "Signal AIRCRACK-TOOL-UNAVAILABLE unless PROGRAM resolves in PATH."
  (or (find-program-in-path program)
      (error 'aircrack-tool-unavailable :program program)))

(defun shell-runner (program args &key timeout-seconds)
  "Default external runner: PATH-guarded argv execution via UIOP.

TIMEOUT-SECONDS is accepted for runner-protocol compatibility and ignored for
bounded commands; long-running captures use AIRODUMP-PROCESS-RUNNER instead."
  (declare (ignore timeout-seconds))
  (ensure-tool-available program)
  (multiple-value-bind (stdout stderr exit-code)
      (uiop:run-program (cons program args)
                        :input nil
                        :output :string
                        :error-output :string
                        :ignore-error-status t)
    (values (or stdout "") (or stderr "") exit-code)))

(defun require-success (program stdout stderr exit-code)
  (unless (or (null exit-code) (zerop exit-code))
    (error 'aircrack-command-failed
           :program program
           :exit-code exit-code
           :output (or stderr stdout)))
  (values))

(defun parse-airmon-interfaces (output)
  "Parse the airmon-ng system/interface table.

Modern airmon-ng prints a tab-separated PHY Interface Driver Chipset table.
Returns (VALUES interfaces issues); interfaces are plists
(:PHY :INTERFACE :DRIVER :CHIPSET)."
  (let (interfaces issues)
    (dolist (line (uiop:split-string (or output "") :separator '(#\Newline)))
      (let* ((line (string-right-trim '(#\Return) line))
             (trimmed (string-trim '(#\Space #\Tab) line)))
        (when (plusp (length trimmed))
          (cond
            ((and (search "interface" (string-downcase trimmed))
                  (or (search "driver" (string-downcase trimmed))
                      (search "phy" (string-downcase trimmed))))
             ;; header row
             )
            (t
             (let ((fields (uiop:split-string line :separator '(#\Tab))))
               (if (>= (length fields) 3)
                   (push (list :phy (string-trim '(#\Space) (nth 0 fields))
                               :interface (string-trim '(#\Space) (nth 1 fields))
                               :driver (string-trim '(#\Space) (nth 2 fields))
                               :chipset (string-trim
                                         '(#\Space)
                                         (join-with-spaces (nthcdr 3 fields))))
                         interfaces)
                   (push (list :line line
                               :reason "not a tab-separated interface row")
                         issues))))))))
    (values (nreverse interfaces) (nreverse issues))))

(defun join-with-spaces (fields)
  (format nil "~{~a~^ ~}" fields))

(defun airmon-ng-status (&key (runner #'shell-runner))
  "Return (VALUES interfaces issues) parsed from `airmon-ng` output."
  (multiple-value-bind (stdout stderr exit-code)
      (funcall runner *airmon-ng-program* '())
    (require-success *airmon-ng-program* stdout stderr exit-code)
    (parse-airmon-interfaces stdout)))

(defun parse-airmon-monitor-interface (output interface)
  "Parse the monitor interface created by `airmon-ng start INTERFACE`.

airmon-ng prints lines such as

  (mac80211 monitor mode vif enabled for [phy0]wlan0 on [phy0]wlan0mon)

Candidates are the bracketed [phyN]<name> captures on monitor-mode lines (the
created vif is the last one), plus the legacy
\"monitor mode enabled on <name>\" form. The first candidate that differs from
INTERFACE wins; NIL when no monitor interface was created."
  (let (candidates)
    (dolist (line (uiop:split-string (or output "") :separator '(#\Newline)))
      (when (search "monitor mode" (string-downcase line))
        (cl-ppcre:do-register-groups (name)
            ("\\[phy[0-9]+\\]([A-Za-z0-9._-]+)" line)
          (push name candidates))
        (cl-ppcre:do-register-groups (name)
            ("monitor mode enabled on ([A-Za-z0-9._-]+)" line)
          (push name candidates))))
    (dolist (candidate (nreverse candidates))
      (unless (string= candidate interface)
        (return-from parse-airmon-monitor-interface (values candidate candidates))))
    (values nil (nreverse candidates))))

(defun airmon-ng-start (interface &key (runner #'shell-runner))
  "Enable monitor mode on INTERFACE.

Returns a plist (:MONITOR-INTERFACE :CANDIDATES :OUTPUT :EXIT-CODE). The
monitor interface name is NIL when airmon-ng reported no vif creation."
  (multiple-value-bind (stdout stderr exit-code)
      (funcall runner *airmon-ng-program* (list "start" interface))
    (require-success *airmon-ng-program* stdout stderr exit-code)
    (multiple-value-bind (monitor candidates)
        (parse-airmon-monitor-interface stdout interface)
      (list :monitor-interface monitor
            :candidates candidates
            :output stdout
            :exit-code exit-code))))

(defun airmon-ng-stop (interface &key (runner #'shell-runner))
  "Disable monitor mode on INTERFACE.

Returns a plist (:STOPPED-P :OUTPUT :EXIT-CODE)."
  (multiple-value-bind (stdout stderr exit-code)
      (funcall runner *airmon-ng-program* (list "stop" interface))
    (require-success *airmon-ng-program* stdout stderr exit-code)
    (list :stopped-p (or (search "(monitor mode disabled)" stdout)
                         (search "removed" stdout :test #'char-equal))
          :output stdout
          :exit-code exit-code)))
