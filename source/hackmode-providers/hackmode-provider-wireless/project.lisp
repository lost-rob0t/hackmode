(in-package :hackmode-provider-wireless)

;;; Projection of parsed airodump-ng captures onto StarIntel wireless
;;; documents (0.10.1 wireless data contracts carried in the v0.9 envelope)
;;; and durable local enqueue through the Hackmode outbox.
;;;
;;; IMPORTANT: these documents are only enqueued locally. The StarIntel server
;;; still pins schema validation below the 0.10.1 wireless release, so
;;; flushing wireless dtypes to a server will be rejected until the server
;;; repins; see README.org.

(defparameter *wireless-dataset* "airodump-ng"
  "Dataset applied to wireless documents produced from airodump-ng captures.")

(defparameter +wireless-schema-version+ "0.9.0"
  "Immutable base/wire schema family of the StarIntel envelope.")

(defparameter +epoch-iso+ "1970-01-01T00:00:00Z")

(defun parse-integer-safe (value)
  "Parse an optionally signed decimal integer; NIL for junk/empty input."
  (let ((trimmed (trim-field (or value ""))))
    (when (plusp (length trimmed))
      (multiple-value-bind (integer position)
          (parse-integer trimmed :junk-allowed t)
        (when (and integer (= position (length trimmed)))
          integer)))))

(defun security-tokens (value)
  "Uppercase alphanumeric tokens of VALUE, split on everything else."
  (remove ""
          (cl-ppcre:split "[^A-Z0-9]+" (string-upcase (trim-field (or value ""))))
          :test #'equal))

(defun enterprise-authentication-p (authentication)
  "True when the Authentication column names an 802.1X/enterprise method."
  (let ((auth (apply #'concatenate 'string
                     (security-tokens (or authentication "")))))
    (or (member auth '("MGT" "8021X" "8021" "EAP" "ENTERPRISE" "ENT")
                :test #'string=)
        (and (plusp (length auth))
             (string= "8021" auth :end2 (min 4 (length auth)))))))

(defun airodump-security (privacy cipher authentication)
  "Map the Privacy/Cipher/Authentication columns onto the security enum.

  | Privacy tokens                     | Authentication | security           |
  |------------------------------------|----------------|--------------------|
  | OPN                                |                | open               |
  | WEP                                |                | wep                |
  | WPA                                | PSK/other      | wpa-psk            |
  | WPA                                | MGT/802.1X/EAP | unknown (no enum)  |
  | WPA2 (incl. WPA2-PSK/-EAP shapes)  | PSK/other      | wpa2-psk           |
  | WPA2                               | MGT/802.1X/EAP | wpa2-enterprise    |
  | WPA3 (incl. WPA3-SAE)              | SAE/PSK/other  | wpa3-psk           |
  | WPA3                               | MGT/802.1X/EAP | wpa3-enterprise    |
  | WPA2+WPA3 / WPA2WPA3 (transition)  | PSK            | wpa2wpa3-psk       |
  | WPA2+WPA3 transition               | MGT/802.1X/EAP | unknown (no enum)  |
  | anything else                      |                | unknown            |

The observed Privacy/Cipher/Authentication strings are preserved verbatim
(trailing/leading padding trimmed) in cipher_suite/auth_mode and the raw CSV
row rides along as document evidence."
  (declare (ignore cipher))
  (let* ((tokens (security-tokens privacy))
         (enterprise (or (enterprise-authentication-p authentication)
                         (intersection tokens '("EAP" "MGT" "ENTERPRISE")
                                       :test #'string=)))
         (wpa2 (or (member "WPA2" tokens :test #'string=)
                   (member "WPA2WPA3" tokens :test #'string=)))
         (wpa3 (or (member "WPA3" tokens :test #'string=)
                   (member "WPA2WPA3" tokens :test #'string=)))
         (mixed (or (member "WPA2WPA3" tokens :test #'string=)
                    (and (member "WPA2" tokens :test #'string=)
                         (member "WPA3" tokens :test #'string=)))))
    (cond
      ((member "OPN" tokens :test #'string=) "open")
      ((and mixed wpa2 wpa3) (if enterprise "unknown" "wpa2wpa3-psk"))
      ((and wpa3 enterprise) "wpa3-enterprise")
      (wpa3 "wpa3-psk")
      ((and wpa2 enterprise) "wpa2-enterprise")
      (wpa2 "wpa2-psk")
      ((member "WPA" tokens :test #'string=) (if enterprise "unknown" "wpa-psk"))
      ((member "WEP" tokens :test #'string=) "wep")
      (t "unknown"))))

(defun channel-band (channel)
  "Band enum from a Wi-Fi channel number: 1-14 => 2.4ghz, 15-196 => 5ghz,
else unknown."
  (cond
    ((<= 1 channel 14) "2.4ghz")
    ((<= 15 channel 196) "5ghz")
    (t "unknown")))

(defun channel-frequency-mhz (channel)
  "Derived center frequency for CHANNEL (Mhz), or NIL.

2.4 GHz: 2407 + 5*channel with the special case 14 => 2484;
5 GHz: 5000 + 5*channel. Matches IEEE center frequencies for the channels
airodump-ng reports; derived, not observed (the CSV has no frequency column)."
  (cond
    ((<= 1 channel 13) (+ 2407 (* 5 channel)))
    ((= channel 14) 2484)
    ((<= 15 channel 196) (+ 5000 (* 5 channel)))
    (t nil)))

(defun airodump-timestamp->iso (value)
  "Convert airodump-ng 'YYYY-MM-DD HH:MM:SS' to ISO-8601 UTC, or NIL.

airodump-ng logs capture-host local time without a zone; this projection
interprets those stamps as UTC for determinism (documented caveat in
README.org)."
  (let ((trimmed (trim-field (or value ""))))
    (multiple-value-bind (match groups)
        (cl-ppcre:scan-to-strings
         "^(\\d{4}-\\d{2}-\\d{2}) (\\d{2}:\\d{2}:\\d{2})$" trimmed)
      (when match
        (concatenate 'string (aref groups 0) "T" (aref groups 1) "Z")))))

(defun hidden-essid-p (essid id-length)
  "True when the ESSID column marks a hidden network.

airodump-ng writes the literal marker `<length: N>' into the ESSID column for
cloaked networks, and ID-length 0 accompanies fully-hidden SSIDs."
  (or (and (stringp essid)
           (cl-ppcre:scan "^<length: *[0-9]+>$" essid))
      (and (stringp id-length)
           (plusp (length id-length))
           (zerop (parse-integer-safe id-length)))))

(defun row-signal-dbm (power)
  "Power column to signal_dbm: NIL for empty, junk, or the -1 sentinel."
  (let ((value (parse-integer-safe power)))
    (when (and value (/= value -1))
      value)))

(defun row-channel (channel)
  "Channel column as an integer; NIL for empty/junk/hopping (-1/0) channels."
  (let ((value (parse-integer-safe channel)))
    (when (and value (>= value 1))
      value)))

(defun mac-string-p (value)
  "True when VALUE normalizes to a well-formed colon MAC."
  (= 12 (length (remove-if-not (lambda (char) (digit-char-p char 16))
                               (or value "")))))

(defun capture-id-source-network-id (capture-id)
  (format nil "airodump-ng:~a" (or capture-id "")))

(defun make-wireless-source (capture now source-id)
  (jsown:new-js
    ("kind" "sensor")
    ("name" "airodump-ng")
    ("access_method" "local-csv")
    ("locator" (or source-id
                   (and (airodump-capture-source-path capture)
                        (namestring (airodump-capture-source-path capture)))
                   (airodump-capture-capture-id capture)
                   ""))
    ("sensor" "airodump-ng")
    ("retrieved_at" now)))

(defun make-row-evidence (row section capture-id index now)
  (declare (ignore section))
  (let* ((raw (etypecase row
                (airodump-ap-row (airodump-ap-row-raw row))
                (airodump-station-row (airodump-station-row-raw row))))
         (section-name (etypecase row
                         (airodump-ap-row "ap")
                         (airodump-station-row "station")))
         (last-seen (etypecase row
                      (airodump-ap-row (airodump-ap-row-last-time-seen row))
                      (airodump-station-row
                       (airodump-station-row-last-time-seen row))))
         (observed-at (airodump-timestamp->iso last-seen))
         (evidence (jsown:new-js
                    ("evidence_id"
                     (format nil "starintel:evidence:~a"
                             (identity-digest (list (or capture-id "")
                                                    section-name
                                                    raw))))
                    ("kind" (format nil "airodump-csv-~a-row" section-name))
                    ("observation" section-name)
                    ("excerpt" raw)
                    ("locator" (format nil "~a#~a/~d"
                                       (or capture-id "") section-name index))
                    ("collected_at" now)
                    ("content_hash" (identity-digest (list raw)))
                    ("hash_algorithm" "sha256"))))
    (when observed-at
      (setf (jsown:val evidence "observed_at") observed-at))
    evidence))

(defun build-wireless-document (&key id dtype dataset data sources evidence
                                  date-added date-updated)
  (jsown:new-js
    ("_id" id)
    ("dataset" dataset)
    ("dtype" dtype)
    ("schema_version" +wireless-schema-version+)
    ("version" 1)
    ("date_added" date-added)
    ("date_updated" date-updated)
    ("sources" sources)
    ("evidence" evidence)
    ("data" data)))

(defun row-doc-ssid (row)
  "SSID for documents: the trimmed ESSID, empty for hidden markers."
  (let ((essid (trim-field (airodump-ap-row-essid row))))
    (if (hidden-essid-p essid (airodump-ap-row-id-length row))
        ""
        essid)))

(defun row-now (first-value last-value now)
  "Deterministic document timestamp: first/last seen, then NOW, then epoch."
  (or (airodump-timestamp->iso first-value)
      (airodump-timestamp->iso last-value)
      now
      +epoch-iso+))

(defun airodump-row->wireless-network-doc (row &key
                                                (capture-id "")
                                                (client-count nil)
                                                (dataset *wireless-dataset*)
                                                (source-id nil)
                                                (now nil)
                                                (index 0))
  "Build a wireless-network jsown document for one AP row.

source_network_id = \"airodump-ng:<CAPTURE-ID>\"; identity follows the
cross-language contract (bssid, ssid-normalized, source_network_id)."
  (let* ((bssid (airodump-ap-row-bssid row))
         (ssid (row-doc-ssid row))
         (source-network-id (capture-id-source-network-id capture-id))
         (channel (row-channel (airodump-ap-row-channel row)))
         (signal (row-signal-dbm (airodump-ap-row-power row)))
         (beacons (parse-integer-safe (airodump-ap-row-beacons row)))
         (first-iso (airodump-timestamp->iso
                     (airodump-ap-row-first-time-seen row)))
         (last-iso (airodump-timestamp->iso
                    (airodump-ap-row-last-time-seen row)))
         (cipher (trim-field (airodump-ap-row-cipher row)))
         (authentication (trim-field (airodump-ap-row-authentication row)))
         (data (jsown:new-js
                ("bssid" (normalize-mac bssid))
                ("ssid" ssid)
                ("security" (airodump-security
                             (airodump-ap-row-privacy row)
                             cipher
                             authentication))
                ("source_network_id" source-network-id))))
    (when (plusp (length cipher))
      (setf (jsown:val data "cipher_suite") cipher))
    (when (plusp (length authentication))
      (setf (jsown:val data "auth_mode") authentication))
    (when channel
      (setf (jsown:val data "channel") channel)
      (setf (jsown:val data "band") (channel-band channel))
      (let ((frequency (channel-frequency-mhz channel)))
        (when frequency
          (setf (jsown:val data "frequency_mhz") frequency))))
    (when signal
      (setf (jsown:val data "signal_dbm") signal))
    (when beacons
      (setf (jsown:val data "observations") beacons))
    (when client-count
      (setf (jsown:val data "client_count") client-count))
    (when first-iso
      (setf (jsown:val data "first_seen") first-iso))
    (when last-iso
      (setf (jsown:val data "last_seen") last-iso))
    (build-wireless-document
     :id (wireless-network-id bssid ssid source-network-id)
     :dtype "wireless-network"
     :dataset dataset
     :data data
     :sources (list (make-wireless-source
                     (make-airodump-capture :capture-id capture-id)
                     (or now last-iso +epoch-iso+)
                     source-id))
     :evidence (list (make-row-evidence row :ap capture-id index
                                        (or now last-iso +epoch-iso+)))
     :date-added (row-now (airodump-ap-row-first-time-seen row)
                          (airodump-ap-row-last-time-seen row)
                          now)
     :date-updated (row-now (airodump-ap-row-last-time-seen row)
                            (airodump-ap-row-first-time-seen row)
                            now))))

(defun station-probe-ssids (row)
  "Probed ESSIDs for documents: trimmed values without hidden markers."
  (remove-if (lambda (probe)
               (or (zerop (length probe))
                   (hidden-essid-p probe nil)))
             (mapcar #'trim-field (airodump-station-row-probed-essids row))))

(defun station-row->wireless-station-doc (row &key
                                              (capture-id "")
                                              (dataset *wireless-dataset*)
                                              (source-id nil)
                                              (now nil)
                                              (index 0))
  "Build a wireless-station jsown document for one station row.

source_device_id = CAPTURE-ID (the CSV filename stem)."
  (let* ((mac (airodump-station-row-mac row))
         (signal (row-signal-dbm (airodump-station-row-power row)))
         (packets (parse-integer-safe (airodump-station-row-packets row)))
         (first-iso (airodump-timestamp->iso
                     (airodump-station-row-first-time-seen row)))
         (last-iso (airodump-timestamp->iso
                    (airodump-station-row-last-time-seen row)))
         (bssid-column (airodump-station-row-bssid row))
         (probes (station-probe-ssids row))
         (data (jsown:new-js
                ("mac" (normalize-mac mac))
                ("station_type" "station")
                ("source_device_id" (or capture-id "")))))
    (when probes
      (setf (jsown:val data "probe_ssids") probes))
    (when (mac-string-p bssid-column)
      (setf (jsown:val data "last_bssid") (normalize-mac bssid-column)))
    (when signal
      (setf (jsown:val data "signal_dbm") signal))
    (when packets
      (setf (jsown:val data "packets") packets))
    (when first-iso
      (setf (jsown:val data "first_seen") first-iso))
    (when last-iso
      (setf (jsown:val data "last_seen") last-iso))
    (build-wireless-document
     :id (wireless-station-id mac (or capture-id ""))
     :dtype "wireless-station"
     :dataset dataset
     :data data
     :sources (list (make-wireless-source
                     (make-airodump-capture :capture-id capture-id)
                     (or now last-iso +epoch-iso+)
                     source-id))
     :evidence (list (make-row-evidence row :station capture-id index
                                        (or now last-iso +epoch-iso+)))
     :date-added (row-now (airodump-station-row-first-time-seen row)
                          (airodump-station-row-last-time-seen row)
                          now)
     :date-updated (row-now (airodump-station-row-last-time-seen row)
                            (airodump-station-row-first-time-seen row)
                            now))))

(defun capture-client-counts (capture)
  "Hash table of normalized AP BSSID => associated station count."
  (let ((counts (make-hash-table :test #'equal)))
    (dolist (station (airodump-capture-station-rows capture))
      (let ((bssid (airodump-station-row-bssid station)))
        (when (mac-string-p bssid)
          (let ((key (normalize-mac bssid)))
            (when (mac-string-p key)
              (incf (gethash key counts 0)))))))
    counts))

(defun capture-default-now (capture)
  "Latest last-seen ISO timestamp in CAPTURE, else the epoch.

Data-derived so re-parsing and re-enqueueing the same capture produce a
byte-identical payload (and therefore no duplicate outbox entries)."
  (let ((latest nil))
    (flet ((consider (value)
             (let ((iso (airodump-timestamp->iso value)))
               (when (and iso (or (null latest) (string> iso latest)))
                 (setf latest iso)))))
      (dolist (row (airodump-capture-ap-rows capture))
        (consider (airodump-ap-row-last-time-seen row)))
      (dolist (row (airodump-capture-station-rows capture))
        (consider (airodump-station-row-last-time-seen row))))
    (or latest +epoch-iso+)))

(defun enqueue-airodump-observations (capture database &key
                                                       (operation nil)
                                                       (source-id nil)
                                                       (dataset *wireless-dataset*)
                                                       (now nil))
  "Enqueue wireless documents for every parsed row of CAPTURE in DATABASE.

Returns (VALUES entries created-count): the durable outbox entries and how
many of them this call created (re-enqueueing a byte-identical payload
creates nothing). Documents are only enqueued locally — the StarIntel server
would reject wireless dtypes until it repins the 0.10.1 schema."
  (let* ((capture-id (airodump-capture-capture-id capture))
         (client-counts (capture-client-counts capture))
         (now (or now (capture-default-now capture)))
         (entries '())
         (created 0))
    (dolist (row (airodump-capture-ap-rows capture))
      (let* ((index (position row (airodump-capture-ap-rows capture)))
             (bssid-key (normalize-mac (airodump-ap-row-bssid row)))
             (doc (airodump-row->wireless-network-doc
                   row
                   :capture-id capture-id
                   :client-count (and (mac-string-p bssid-key)
                                      (gethash bssid-key client-counts))
                   :dataset dataset
                   :source-id source-id
                   :now now
                   :index index)))
        (multiple-value-bind (entry created-p)
            (hackmode:enqueue-starintel-json database doc :operation operation)
          (push entry entries)
          (when created-p
            (incf created)))))
    (dolist (row (airodump-capture-station-rows capture))
      (let ((doc (station-row->wireless-station-doc
                  row
                  :capture-id capture-id
                  :dataset dataset
                  :source-id source-id
                  :now now
                  :index (position row (airodump-capture-station-rows capture)))))
        (multiple-value-bind (entry created-p)
            (hackmode:enqueue-starintel-json database doc :operation operation)
          (push entry entries)
          (when created-p
            (incf created)))))
    (values (nreverse entries) created)))
