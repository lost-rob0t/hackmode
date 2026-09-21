(in-package :hackmode-provider-wireless)

;;; Deterministic identity shared byte-for-byte with tools/wireless (Python).
;;;
;;; The Python authority is tools/wireless/src/hackmode_wireless/transport.py:
;;;
;;;   normalize_mac   strip non-hex-digit chars; 12 remaining digits ->
;;;                   lower-case colon form, else strip().lower() fallback
;;;   normalize_ssid  trim + squeeze internal whitespace + str.casefold
;;;   deterministic_id "starintel:<dtype>:<hex(sha256(identity-key))>" with the
;;;                   identity key joined by the unit separator U+001F
;;;
;;; Python str.casefold applies full Unicode case folding per code point, which
;;; Common Lisp has no portable equivalent for, so this file loads the generated
;;; +casefold-table+ (casefold.txt) covering every code point whose casefold
;;; differs from the identity mapping. Regeneration instructions live in
;;; README.org.

(defparameter +python-whitespace-codepoints+
  '(#x09 #x0a #x0b #x0c #x0d #x1c #x1d #x1e #x1f #x20 #x85 #xa0 #x1680
    #x2000 #x2001 #x2002 #x2003 #x2004 #x2005 #x2006 #x2007 #x2008 #x2009
    #x200a #x2028 #x2029 #x202f #x205f #x3000)
  "Code points for which CPython str.isspace() is true; this is also exactly
the re \\s character class for str patterns. Verified against CPython 3.14 via
the tools/wireless virtualenv; do not edit by hand.")

(defparameter +python-whitespace-bag+
  (coerce (mapcar #'code-char +python-whitespace-codepoints+) 'string)
  "Bag of Python whitespace characters for STRING-TRIM.")

(defun python-whitespace-p (char)
  (find char +python-whitespace-bag+ :test #'char=))

(defun casefold-data-path ()
  (asdf:system-relative-pathname :hackmode-provider-wireless "casefold.txt"))

(defun load-casefold-table (path)
  "Read the generated full casefolding table from PATH into a hash table."
  (with-open-file (stream path :if-does-not-exist :error)
    (loop with table = (make-hash-table :test #'eql)
          for line = (read-line stream nil nil)
          while line
          for parts = (uiop:split-string line :separator " ")
          when (and (second parts) (plusp (length (second parts))))
            do (setf (gethash (code-char (parse-integer (first parts) :radix 16)) table)
                     (map 'string
                          (lambda (token)
                            (code-char (parse-integer token :radix 16)))
                          (uiop:split-string (second parts) :separator '(#\,))))
          finally (return table))))

(defparameter *casefold-table* (load-casefold-table (casefold-data-path))
  "Full Unicode casefolding table generated from CPython str.casefold.")

(defun casefold-string (value)
  "Casefold VALUE per code point exactly like Python str.casefold."
  (with-output-to-string (out)
    (loop for char across value
          for folded = (gethash char *casefold-table*)
          do (if folded
                 (write-string folded out)
                 (write-char char out)))))

(defun squeeze-python-whitespace (value)
  "Replace runs of Python whitespace with a single space, re.sub(\"\\s+\", \" \")."
  (with-output-to-string (out)
    (loop with previous-whitespace = nil
          for char across value
          for whitespace = (python-whitespace-p char)
          do (cond
               ((and whitespace previous-whitespace))
               (whitespace (write-char #\Space out))
               (t (write-char char out)))
             (setf previous-whitespace whitespace))))

(defun normalize-mac (mac)
  "Normalize a MAC/BSSID exactly like the Python authority.

Twelve hex digits (after removing every non-hex-digit character) become the
lower-case colon form. Anything else falls back to trimming Python whitespace
and STRING-DOWNCASE; STRING-DOWNCASE equals Python str.lower() for ASCII input,
so exotic non-MAC strings may diverge from Python on that fallback path."
  (let ((digits (remove-if-not (lambda (char) (digit-char-p char 16)) mac)))
    (if (= 12 (length digits))
        (string-downcase
         (with-output-to-string (out)
           (loop for char across digits
                 for index from 0
                 do (when (and (plusp index) (zerop (mod index 2)))
                      (write-char #\: out))
                    (write-char char out))))
        (string-downcase (string-trim +python-whitespace-bag+ mac)))))

(defun normalize-ssid (ssid)
  "Normalize an SSID exactly like the Python authority.

trim + squeeze internal whitespace + casefold. Non-strings (NIL) normalize to
the empty string."
  (if (stringp ssid)
      (casefold-string
       (squeeze-python-whitespace
        (string-trim +python-whitespace-bag+ ssid)))
      ""))

(defun join-identity-parts (parts)
  (with-output-to-string (out)
    (loop for part in parts
          for first = t then nil
          do (progn
               (unless first
                 (write-char (code-char #x1f) out))
               (write-string part out)))))

(defun identity-digest (parts)
  "Lower-case hex SHA-256 over the unit-separator (U+001F) join of PARTS."
  (ironclad:byte-array-to-hex-string
   (ironclad:digest-sequence
    :sha256
    (babel:string-to-octets (join-identity-parts parts) :encoding :utf-8))))

(defun deterministic-id (dtype parts)
  "Stable document id: starintel:<dtype>:<sha256-of-identity-key>."
  (format nil "starintel:~a:~a" dtype (identity-digest parts)))

(defun wireless-network-id (bssid ssid source-network-id)
  "Deterministic wireless-network id over (bssid, ssid-normalized, source_network_id)."
  (deterministic-id
   "wireless-network"
   (list (normalize-mac bssid)
         (normalize-ssid ssid)
         (or source-network-id ""))))

(defun wireless-station-id (mac source-device-id)
  "Deterministic wireless-station id over (mac, source_device_id)."
  (deterministic-id
   "wireless-station"
   (list (normalize-mac mac)
         (or source-device-id ""))))
