(in-package :hackmode-provider-wireless)

;;; airodump-ng CSV parsing.
;;;
;;; Format: two sections, each introduced by a header line.
;;;
;;;   BSSID, First time seen, Last time seen, channel, Speed, Privacy, Cipher,
;;;   Authentication, Power, # beacons, # IV, LAN IP, ID-length, ESSID, Key
;;;
;;;   Station MAC, First time seen, Last time seen, Power, # packets, BSSID,
;;;   Probed ESSIDs
;;;
;;; airodump-ng never quotes fields, so an ESSID containing commas produces
;;; extra comma-separated fields. The parse rule (documented in README.org):
;;;
;;;   * columns 0..12 (BSSID through ID-length) are fixed from the left;
;;;   * the final field is the (usually empty) Key;
;;;   * every field in between joins back onto the ESSID with literal commas;
;;;   * when the row overflowed and ID-length is an integer, the join is
;;;     verified (and, if possible, corrected) against that exact length.
;;;
;;; Lossless evidence: every parsed record carries the original row text in
;;; RAW (without its line terminator), and malformed rows are preserved in a
;;; PARSE-ISSUES list instead of being dropped.

(defstruct (airodump-parse-issue
            (:constructor make-parse-issue
                          (&key raw section reason)))
  raw section reason)

(defstruct (airodump-ap-row (:constructor make-ap-row))
  raw bssid first-time-seen last-time-seen channel speed privacy cipher
  authentication power beacons ivs lan-ip id-length essid key
  essid-comma-recovered)

(defstruct (airodump-station-row
            (:constructor make-station-row
                          (&key raw mac first-time-seen last-time-seen
                             power packets bssid probed-essids)))
  raw mac first-time-seen last-time-seen power packets bssid probed-essids)

(defstruct airodump-capture
  capture-id source-path ap-rows station-rows parse-issues)

(defconstant +ap-fixed-columns+ 13
  "Columns before ESSID: BSSID, First time seen, Last time seen, channel,
Speed, Privacy, Cipher, Authentication, Power, # beacons, # IV, LAN IP,
ID-length.")

(defun split-csv-fields (line)
  "Split LINE on commas, preserving empty fields (including trailing ones)."
  (let ((parts '())
        (start 0)
        (length (length line)))
    (loop for index from 0 below length
          when (char= (char line index) #\,)
            do (push (subseq line start index) parts)
               (setf start (1+ index)))
    (nreverse (cons (subseq line start length) parts))))

(defun trim-field (field)
  (string-trim '(#\Space #\Tab) field))

(defun join-commas (fields)
  (with-output-to-string (out)
    (loop for field in fields
          for first = t then nil
          do (progn
               (unless first
                 (write-char #\, out))
               (write-string field out)))))

(defun ap-header-p (line)
  (let ((down (string-downcase line)))
    (and (<= 5 (length down))
         (string= "bssid" (subseq down 0 5))
         (search "first time seen" down)
         (search "essid" down))))

(defun station-header-p (line)
  (let ((down (string-downcase line)))
    (and (search "station mac" down)
         (search "first time seen" down))))

(defun essid-by-id-length (fields start target-length)
  "Recover an ESSID containing commas using the ID-length column.

Consume comma-joined trimmed fields starting at START until the accumulated
length reaches TARGET-LENGTH. The recovery is accepted only when the length is
hit exactly and exactly one field (the Key) remains afterwards; otherwise NIL."
  (loop with accumulated = ""
        for index from start below (1- (length fields))
        for field = (elt fields index)
        for joined = (if (zerop (length accumulated))
                         field
                         (concatenate 'string accumulated "," field))
        when (>= (length joined) target-length)
          do (return (if (and (= (length joined) target-length)
                              (= 1 (- (length fields) index 1)))
                         joined
                         nil))
        do (setf accumulated joined)
        finally (return nil)))

(defun parse-ap-line (raw)
  "Parse one AP section row. Returns the row and NIL, or NIL and a parse issue."
  (let* ((fields (mapcar #'trim-field (split-csv-fields raw)))
         (count (length fields)))
    (if (< count 15)
        (values
         nil
         (make-parse-issue
          :raw raw
          :section :ap
          :reason (format nil
                          "AP row has ~d comma-separated fields; at least 15 required"
                          count)))
        (let* ((fixed (subseq fields 0 +ap-fixed-columns+))
               (key (elt fields (1- count)))
               (middle (subseq fields +ap-fixed-columns+ (1- count)))
               (essid (join-commas middle))
               (recovered (> count 15))
               (id-length (parse-integer-safe (nth 12 fields))))
          ;; airodump never quotes ESSIDs; when the row overflowed and
          ;; ID-length is available, trust the exact length over the join.
          (when (and recovered id-length (>= id-length 0))
            (let ((candidate (essid-by-id-length fields +ap-fixed-columns+ id-length)))
              (when candidate
                (setf essid candidate))))
          (values
           (make-ap-row
            :raw raw
            :bssid (nth 0 fixed)
            :first-time-seen (nth 1 fixed)
            :last-time-seen (nth 2 fixed)
            :channel (nth 3 fixed)
            :speed (nth 4 fixed)
            :privacy (nth 5 fixed)
            :cipher (nth 6 fixed)
            :authentication (nth 7 fixed)
            :power (nth 8 fixed)
            :beacons (nth 9 fixed)
            :ivs (nth 10 fixed)
            :lan-ip (nth 11 fixed)
            :id-length (nth 12 fixed)
            :essid essid
            :key key
            :essid-comma-recovered recovered)
           nil)))))

(defun parse-station-line (raw)
  "Parse one station section row. Returns the row and NIL, or NIL and an issue."
  (let* ((fields (mapcar #'trim-field (split-csv-fields raw)))
         (count (length fields)))
    (if (< count 6)
        (values
         nil
         (make-parse-issue
          :raw raw
          :section :station
          :reason (format nil
                          "station row has ~d comma-separated fields; at least 6 required"
                          count)))
        (values
         (make-station-row
          :raw raw
          :mac (nth 0 fields)
          :first-time-seen (nth 1 fields)
          :last-time-seen (nth 2 fields)
          :power (nth 3 fields)
          :packets (nth 4 fields)
          :bssid (nth 5 fields)
          :probed-essids (remove "" (nthcdr 6 fields) :test #'equal))
         nil))))

(defun split-csv-lines (text)
  "Split TEXT into lines, tolerating CRLF terminators.

Returned lines keep everything except the terminator characters."
  (let ((lines '())
        (start 0)
        (length (length text)))
    (loop for index from 0 below length
          when (char= (char text index) #\Newline)
            do (let ((line (subseq text start index)))
                 (when (and (plusp (length line))
                            (char= (char line (1- (length line))) #\Return))
                   (setf line (subseq line 0 (1- (length line)))))
                 (push line lines)
                 (setf start (1+ index))))
    (let ((tail (subseq text start length)))
      (nreverse
       (cons (if (and (plusp (length tail))
                      (char= (char tail (1- (length tail))) #\Return))
                 (subseq tail 0 (1- (length tail)))
                 tail)
             lines)))))

(defun parse-airodump-csv (text &key (capture-id ""))
  "Parse airodump-ng CSV TEXT into an AIRODUMP-CAPTURE.

Tolerates CRLF line endings, blank lines between sections, a missing station
section, and malformed rows (which are preserved in PARSE-ISSUES with their
raw text)."
  (let ((section :preamble)
        ap-rows station-rows parse-issues)
    (dolist (raw (split-csv-lines text))
      (let ((trimmed (string-trim '(#\Space #\Tab #\Return) raw)))
        (when (plusp (length trimmed))
          (cond
            ((ap-header-p trimmed) (setf section :ap))
            ((station-header-p trimmed) (setf section :station))
            ((eq section :ap)
             (multiple-value-bind (row issue) (parse-ap-line raw)
               (if row
                   (push row ap-rows)
                   (push issue parse-issues))))
            ((eq section :station)
             (multiple-value-bind (row issue) (parse-station-line raw)
               (if row
                   (push row station-rows)
                   (push issue parse-issues))))
            (t
             (push (make-parse-issue
                    :raw raw
                    :section :preamble
                    :reason "line appears before the first section header")
                   parse-issues))))))
    (make-airodump-capture
     :capture-id capture-id
     :source-path nil
     :ap-rows (nreverse ap-rows)
     :station-rows (nreverse station-rows)
     :parse-issues (nreverse parse-issues))))

(defun capture-id-from-path (path)
  "Capture id for PATH: the CSV filename stem (e.g. capture-01 for
capture-01.csv), as written by airodump-ng's -w prefix numbering."
  (pathname-name path))

(defun parse-airodump-csv-file (path)
  "Parse the airodump-ng CSV file at PATH with CAPTURE-ID from its filename stem."
  (let* ((capture (parse-airodump-csv
                   (uiop:read-file-string path)
                   :capture-id (capture-id-from-path path))))
    (setf (airodump-capture-source-path capture) path)
    capture))

(defun parse-airodump-csv-path (path)
  "Alias for PARSE-AIRODUMP-CSV-FILE."
  (parse-airodump-csv-file path))
