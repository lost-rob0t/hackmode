(in-package :hackmode-provider-wireless)

;;; airodump-ng capture runner.
;;;
;;; v1 scope: capture ONLY (airodump-ng -w prefix --output-format csv with a
;;; bounded duration). Packet injection (aireplay-ng) and key recovery
;;; (aircrack-ng proper) are explicitly out of scope; see README.org.
;;;
;;; Duration bounding: no other Hackmode provider bounds a shell command, so
;;; this module uses UIOP:LAUNCH-PROGRAM with stdout/stderr redirected to
;;; temporary files (the interactive screen output would otherwise fill the
;;; pipe buffer), a polling deadline, a best-effort terminate, and a final
;;; wait. A successful bounded capture is judged by the presence of the CSV
;;; file, not by the exit status of the killed process.

(defparameter *airodump-ng-program*
  (or (uiop:getenv "HACKMODE_AIRODUMP_NG_PROGRAM") "airodump-ng")
  "airodump-ng executable used by the wireless provider.")

(defparameter *airodump-poll-interval* 0.25
  "Seconds between liveness checks while waiting out a capture duration.")

(defun fresh-airodump-prefix ()
  (merge-pathnames
   (format nil "hackmode-airodump-~36r-~36r"
           (get-universal-time)
           (random most-positive-fixnum))
   (uiop:temporary-directory)))

(defun fresh-airodump-stdout-path (kind)
  (merge-pathnames
   (format nil "hackmode-airodump-~a-~36r-~36r.txt"
           kind (get-universal-time) (random most-positive-fixnum))
   (uiop:temporary-directory)))

(defun airodump-argv (interface channels output-prefix extra-args)
  "Build the airodump-ng argv list for a bounded CSV capture."
  (append
   (list "-w" (namestring output-prefix)
         "--output-format" "csv")
   (when (and channels (plusp (length channels)))
     (list "-c" channels))
   extra-args
   (list interface)))

(defun normalize-channel-spec (channels)
  "Reduce CHANNELS (string or list of integers/strings) to a comma string."
  (cond
    ((null channels) nil)
    ((stringp channels) (string-trim '(#\Space) channels))
    (t (format nil "~{~a~^,~}" channels))))

(defun airodump-process-runner (program argv &key timeout-seconds)
  "Bounded external runner for airodump-ng.

Launches PROGRAM with ARGV, polls until TIMEOUT-SECONDS elapse, then
terminates the process and returns (VALUES stdout stderr exit-code). Output
accumulates in temporary files to avoid pipe-buffer deadlock against
airodump-ng's screen output."
  (unless (and timeout-seconds (plusp timeout-seconds))
    (error "airodump-ng capture requires a positive :DURATION-SECONDS; ~
unbounded captures are not supported"))
  (ensure-tool-available program)
  (let* ((stdout-path (fresh-airodump-stdout-path "stdout"))
         (stderr-path (fresh-airodump-stdout-path "stderr"))
         (process (uiop:launch-program (cons program argv)
                                       :input nil
                                       :output stdout-path
                                       :error-output stderr-path))
         (deadline (+ (get-universal-time) (ceiling timeout-seconds))))
    (unwind-protect
         (loop while (and (uiop:process-alive-p process)
                          (< (get-universal-time) deadline))
               do (sleep *airodump-poll-interval*))
      (when (uiop:process-alive-p process)
        (ignore-errors (uiop:terminate-process process)))
      (ignore-errors (uiop:wait-process process)))
    (values
     (or (ignore-errors (uiop:read-file-string stdout-path)) "")
     (or (ignore-errors (uiop:read-file-string stderr-path)) "")
     ;; the process was killed by us after the deadline; exit status is not
     ;; meaningful for a successful bounded capture
     0)))

(defun find-airodump-csv (output-prefix)
  "Locate the CSV airodump-ng wrote for OUTPUT-PREFIX.

airodump-ng appends -01 before the extension (prefix-01.csv) and rotates the
counter on later runs; the lowest existing counter wins."
  (let ((candidates
          (sort
           (remove-if
            #'null
            (loop for counter from 1 to 99
                  for path = (parse-namestring
                              (format nil "~a-~2,'0d.csv"
                                      (namestring output-prefix) counter))
                  when (probe-file path)
                    collect path))
           #'string< :key #'namestring)))
    (first candidates)))

(defun run-airodump (interface &key
                                 (channels nil)
                                 (output-prefix nil)
                                 (duration-seconds nil)
                                 (extra-args nil)
                                 (runner #'airodump-process-runner))
  "Run a bounded airodump-ng CSV capture on INTERFACE.

KEYS:
  CHANNELS          channel spec (string \"1,6\" or list) passed as -c
  OUTPUT-PREFIX     -w prefix; a fresh temporary prefix when NIL
  DURATION-SECONDS  required by the default runner; the process is
                    terminated after this many seconds
  EXTRA-ARGS        appended before the interface (e.g. band filters)
  RUNNER            injected runner called as
                    (funcall runner program argv :timeout-seconds duration)

Returns the CSV pathname airodump-ng produced. RUNNER returning without
creating a CSV signals an error carrying stderr."
  (let* ((prefix (or output-prefix (fresh-airodump-prefix)))
         (channel-spec (normalize-channel-spec channels))
         (argv (airodump-argv interface channel-spec prefix extra-args)))
    (multiple-value-bind (stdout stderr exit-code)
        (funcall runner *airodump-ng-program* argv
                 :timeout-seconds duration-seconds)
      (declare (ignore stdout exit-code))
      (let ((csv (find-airodump-csv prefix)))
        (unless csv
          (error 'aircrack-command-failed
                 :program *airodump-ng-program*
                 :exit-code :no-csv
                 :output (format
                          nil
                          "no CSV produced at prefix ~a: ~a"
                          prefix
                          (string-trim '(#\Space #\Tab #\Newline #\Return)
                                       (or stderr "")))))
        csv))))
