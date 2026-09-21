(defpackage :hackmode-provider-wireless-tests
  (:use :cl)
  (:export :run-tests))

(in-package :hackmode-provider-wireless-tests)

(defun assert-equal (expected actual &optional (label "values"))
  (assert (equal expected actual) ()
          "Expected ~a to be ~s, got ~s" label expected actual))

(defun fixture-path (name)
  (asdf:system-relative-pathname
   :hackmode-provider-wireless
   (format nil "tests/fixtures/~a" name)))

(defun fresh-test-path ()
  (merge-pathnames
   (format nil "hackmode-provider-wireless-~a/" (tek9:make-key-id))
   (uiop:temporary-directory)))

(defun remove-test-path (path)
  (ignore-errors
   (uiop:delete-directory-tree path :validate t :if-does-not-exist :ignore)))

;;; Golden ids computed by tools/wireless (the Python identity authority)
;;; via hackmode_wireless.transport.wireless_network_id /
;;; wireless_station_id on 2026-09-20. Regeneration commands live in
;;; README.org; these constants pin cross-language parity.

(defparameter +golden-network-homenet+
  "starintel:wireless-network:a6395a156f6a715d94f6da1c6ffac7f037021c3e81262be49afda33788b1f4d1")

(defparameter +golden-network-mixed-case+
  "starintel:wireless-network:d758971e99629738e849c3f12e3b45f0ff9a36d44d33bfd94ef380be1d60d5a3")

(defparameter +golden-network-comma+
  "starintel:wireless-network:1e20fad33ed88f502d6aa4b2a058d790ed6266869491ab76bce4931e8a5c29b9")

(defparameter +golden-network-hidden+
  "starintel:wireless-network:f45cc18b40ad852c90d989f5ed2f2abe0b0277b39be12c23ccd143ed8ff5fa6f")

(defparameter +golden-network-unicode+
  "starintel:wireless-network:69ac02b0c7e97425fd275741919c71834ce89eaa0807319542187d1c23cb64a8")

(defparameter +golden-station-one+
  "starintel:wireless-station:6113d5c6a8a7c78a0f81daddfbab3e71c6732b7359563fdaa4e2212541da214a")

(defparameter +golden-station-two+
  "starintel:wireless-station:3aeb0bff8db083452368db56177cc8af27c4576e767ba7e921191035231afaa0")

(defun run-identity-test ()
  (assert-equal "aa:bb:cc:dd:ee:ff"
                (hackmode-provider-wireless:normalize-mac "AA:BB:CC:DD:EE:FF")
                "colon MAC normalization")
  (assert-equal "aa:bb:cc:dd:ee:ff"
                (hackmode-provider-wireless:normalize-mac "aa-bb-cc-dd-ee-ff")
                "dash MAC normalization")
  (assert-equal "01:23:45:67:89:ab"
                (hackmode-provider-wireless:normalize-mac "0123456789AB")
                "bare MAC normalization")
  (assert-equal "" (hackmode-provider-wireless:normalize-ssid nil)
                "non-string SSID")
  (assert-equal "homenet"
                (hackmode-provider-wireless:normalize-ssid " HomeNet ")
                "trimmed casefolded SSID")
  (assert-equal "mixed case ssid"
                (hackmode-provider-wireless:normalize-ssid "Mixed  CASE  ssid")
                "squeezed internal whitespace")
  (assert-equal "comma,net"
                (hackmode-provider-wireless:normalize-ssid " comma,net ")
                "commas are not whitespace")
  (assert-equal "ünïcode ss wifi"
                (hackmode-provider-wireless:normalize-ssid "Ünïcode ß WiFi")
                "full casefold (sharp s -> ss)")
  ;; Python parity goldens
  (assert-equal +golden-network-homenet+
                (hackmode-provider-wireless:wireless-network-id
                 "00:11:22:33:44:55" "HomeNet" "airodump-ng:fixture-a-01")
                "Python golden: plain network id")
  (assert-equal +golden-network-mixed-case+
                (hackmode-provider-wireless:wireless-network-id
                 "AA:BB:CC:DD:EE:FF" "Mixed  CASE  ssid" "airodump-ng:fixture-a-01")
                "Python golden: case/space folding")
  (assert-equal +golden-network-comma+
                (hackmode-provider-wireless:wireless-network-id
                 "aa-bb-cc-dd-ee-ff" " comma,net " "airodump-ng:fixture-b-01")
                "Python golden: comma ssid")
  (assert-equal +golden-network-hidden+
                (hackmode-provider-wireless:wireless-network-id
                 "0123456789AB" "" "airodump-ng:fixture-c-01")
                "Python golden: empty ssid")
  (assert-equal +golden-network-unicode+
                (hackmode-provider-wireless:wireless-network-id
                 "00:11:22:33:44:55" "Ünïcode ß WiFi" "airodump-ng:fixture-d-01")
                "Python golden: unicode ssid")
  (assert-equal +golden-station-one+
                (hackmode-provider-wireless:wireless-station-id
                 "11:22:33:44:55:66" "airodump-ng:fixture-a-01")
                "Python golden: station id")
  (assert-equal +golden-station-two+
                (hackmode-provider-wireless:wireless-station-id
                 "F0:9F:C0:DE:00:01" "airodump-ng:fixture-b-01")
                "Python golden: station id 2"))

(defun run-parser-multi-test ()
  (let ((capture (hackmode-provider-wireless:parse-airodump-csv-file
                  (fixture-path "multi.csv"))))
    (assert-equal "multi" (hackmode-provider-wireless:airodump-capture-capture-id
                           capture)
                  "capture id from filename stem")
    (assert (= 4 (length (hackmode-provider-wireless:airodump-capture-ap-rows
                          capture))))
    (assert (= 4 (length
                  (hackmode-provider-wireless:airodump-capture-station-rows
                   capture))))
    (assert (null (hackmode-provider-wireless:airodump-capture-parse-issues
                   capture)))
    (let ((ap (first (hackmode-provider-wireless:airodump-capture-ap-rows
                      capture))))
      (assert-equal "AA:BB:CC:DD:EE:FF"
                    (hackmode-provider-wireless:airodump-ap-row-bssid ap)
                    "AP bssid")
      (assert-equal "2026-09-20 09:00:00"
                    (hackmode-provider-wireless:airodump-ap-row-first-time-seen ap)
                    "AP first seen")
      (assert-equal "6" (hackmode-provider-wireless:airodump-ap-row-channel ap)
                    "AP channel")
      (assert-equal "WPA2" (hackmode-provider-wireless:airodump-ap-row-privacy ap)
                    "AP privacy")
      (assert-equal "CCMP" (hackmode-provider-wireless:airodump-ap-row-cipher ap)
                    "AP cipher")
      (assert-equal "PSK"
                    (hackmode-provider-wireless:airodump-ap-row-authentication ap)
                    "AP authentication")
      (assert-equal "-50" (hackmode-provider-wireless:airodump-ap-row-power ap)
                    "AP power")
      (assert-equal "120" (hackmode-provider-wireless:airodump-ap-row-beacons ap)
                    "AP beacons")
      (assert-equal "8" (hackmode-provider-wireless:airodump-ap-row-id-length ap)
                    "AP id-length")
      (assert-equal "HomeNet" (hackmode-provider-wireless:airodump-ap-row-essid ap)
                    "AP essid")
      (assert-equal "" (hackmode-provider-wireless:airodump-ap-row-key ap)
                    "AP key")
      (assert (not (hackmode-provider-wireless:airodump-ap-row-essid-comma-recovered
                    ap)))
      (assert (search "AA:BB:CC:DD:EE:FF, 2026-09-20 09:00:00"
                      (hackmode-provider-wireless:airodump-ap-row-raw ap))
              ()
              "raw row is preserved on the parsed record"))
    (let ((station (fourth
                    (hackmode-provider-wireless:airodump-capture-station-rows
                     capture))))
      (assert-equal "DD:00:11:22:33:47"
                    (hackmode-provider-wireless:airodump-station-row-mac station)
                    "station mac")
      (assert-equal "-1"
                    (hackmode-provider-wireless:airodump-station-row-power station)
                    "station power sentinel")
      (assert-equal "(not associated)"
                    (hackmode-provider-wireless:airodump-station-row-bssid station)
                    "not-associated marker")
      (assert-equal '("HomeNet")
                    (hackmode-provider-wireless:airodump-station-row-probed-essids
                     station)
                    "station probed essids"))))

(defun run-hidden-test ()
  (let* ((capture (hackmode-provider-wireless:parse-airodump-csv-file
                   (fixture-path "hidden.csv")))
         (rows (hackmode-provider-wireless:airodump-capture-ap-rows capture)))
    (assert (= 2 (length rows)))
    (let ((zeroth (first rows)))
      (assert-equal "<length:  0>"
                    (hackmode-provider-wireless:airodump-ap-row-essid zeroth)
                    "hidden marker kept in record")
      (assert-equal "0"
                    (hackmode-provider-wireless:airodump-ap-row-id-length zeroth)
                    "hidden id-length")
      (assert-equal ""
                    (hackmode-provider-wireless::row-doc-ssid zeroth)
                    "hidden ssid projects to empty"))
    (let ((ninth (second rows)))
      (assert (hackmode-provider-wireless:hidden-essid-p
               (hackmode-provider-wireless:airodump-ap-row-essid ninth)
               (hackmode-provider-wireless:airodump-ap-row-id-length ninth))
              ()
              "length marker row is hidden"))))

(defun run-security-matrix-test ()
  (let* ((capture (hackmode-provider-wireless:parse-airodump-csv-file
                   (fixture-path "security-matrix.csv")))
         (rows (hackmode-provider-wireless:airodump-capture-ap-rows capture))
         (expected '(("Case01" . "wpa2-psk")
                     ("Case02" . "wpa2-psk")
                     ("Case03" . "wpa3-psk")
                     ("Case04" . "wpa2wpa3-psk")
                     ("Case05" . "wpa2-enterprise")
                     ("Case06" . "wpa2-enterprise")
                     ("Case07" . "wpa-psk")
                     ("Case08" . "open")
                     ("Case09" . "wep")
                     ("Case10" . "wpa3-psk")
                     ("Case11" . "unknown")
                     ("Case12" . "unknown"))))
    (assert-equal (length expected) (length rows) "matrix row count")
    (loop for row in rows
          for (essid . security) in expected
          do (assert-equal essid
                           (hackmode-provider-wireless:airodump-ap-row-essid row)
                           "matrix row order")
             (assert-equal
              security
              (hackmode-provider-wireless:airodump-security
               (hackmode-provider-wireless:airodump-ap-row-privacy row)
               (hackmode-provider-wireless:airodump-ap-row-cipher row)
               (hackmode-provider-wireless:airodump-ap-row-authentication row))
              (format nil "security mapping for ~a" essid)))
    ;; 5 GHz band/frequency mapping off channel 44
    (let ((doc (hackmode-provider-wireless:airodump-row->wireless-network-doc
                (fourth (hackmode-provider-wireless:airodump-capture-ap-rows
                         (hackmode-provider-wireless:parse-airodump-csv-file
                          (fixture-path "multi.csv"))))
                :capture-id "multi")))
      (assert-equal "5ghz"
                    (jsown:val-safe (jsown:val doc "data") "band")
                    "channel 44 band")
      (assert-equal 5220
                    (jsown:val-safe (jsown:val doc "data") "frequency_mhz")
                    "channel 44 frequency"))))

(defun run-comma-essid-test ()
  (let* ((capture (hackmode-provider-wireless:parse-airodump-csv-file
                   (fixture-path "comma-essid.csv")))
         (rows (hackmode-provider-wireless:airodump-capture-ap-rows capture)))
    (assert (= 3 (length rows)))
    (let ((first-row (first rows)))
      (assert-equal "Net,Work,Inc"
                    (hackmode-provider-wireless:airodump-ap-row-essid first-row)
                    "comma ESSID recovered by left-fixed/right-fixed join")
      (assert (hackmode-provider-wireless:airodump-ap-row-essid-comma-recovered
               first-row))
      (assert-equal ""
                    (hackmode-provider-wireless:airodump-ap-row-key first-row)
                    "key stays empty after recovery")
      ;; id-length 12 confirms the recovery
      (assert-equal 12
                    (length
                     (hackmode-provider-wireless:airodump-ap-row-essid first-row))))
    (let ((second-row (second rows)))
      (assert-equal "a,b"
                    (hackmode-provider-wireless:airodump-ap-row-essid second-row)
                    "short comma ESSID"))
    (let ((third-row (third rows)))
      ;; id-length (5) disagrees with any valid recovery; the documented
      ;; primary join wins and the raw row is still retained
      (assert-equal "wrong,extra"
                    (hackmode-provider-wireless:airodump-ap-row-essid third-row)
                    "unverifiable comma ESSID falls back to primary join")
      (assert (search "wrong,extra"
                      (hackmode-provider-wireless:airodump-ap-row-raw third-row))
              ()
              "raw row retained for unverifiable recovery"))))

(defun run-crlf-test ()
  (let* ((crlf (hackmode-provider-wireless:parse-airodump-csv-file
                (fixture-path "crlf.csv")))
         (lf (hackmode-provider-wireless:parse-airodump-csv-file
              (fixture-path "no-stations.csv"))))
    (assert-equal (mapcar #'hackmode-provider-wireless:airodump-ap-row-bssid
                          (hackmode-provider-wireless:airodump-capture-ap-rows lf))
                  (mapcar #'hackmode-provider-wireless:airodump-ap-row-bssid
                          (hackmode-provider-wireless:airodump-capture-ap-rows crlf))
                  "CRLF and LF parse identically (bssids)")
    (assert-equal (mapcar #'hackmode-provider-wireless:airodump-ap-row-essid
                          (hackmode-provider-wireless:airodump-capture-ap-rows lf))
                  (mapcar #'hackmode-provider-wireless:airodump-ap-row-essid
                          (hackmode-provider-wireless:airodump-capture-ap-rows crlf))
                  "CRLF and LF parse identically (essids)")
    (assert (null (hackmode-provider-wireless:airodump-capture-parse-issues crlf))
            ()
            "CRLF captures produce no parse issues")
    (assert
      (not (find #\Return
                 (hackmode-provider-wireless:airodump-ap-row-raw
                  (first (hackmode-provider-wireless:airodump-capture-ap-rows crlf)))))
      ()
      "raw rows exclude the CR terminator")))

(defun run-no-stations-test ()
  (let ((capture (hackmode-provider-wireless:parse-airodump-csv-file
                  (fixture-path "no-stations.csv"))))
    (assert (null (hackmode-provider-wireless:airodump-capture-station-rows capture)))
    (let* ((counts (hackmode-provider-wireless:capture-client-counts capture))
           (doc (hackmode-provider-wireless:airodump-row->wireless-network-doc
                 (first (hackmode-provider-wireless:airodump-capture-ap-rows capture))
                 :capture-id "no-stations")))
      (declare (ignore counts))
      (assert (null (jsown:val-safe (jsown:val doc "data") "client_count"))
              ()
              "no station section means no client_count"))))

(defun run-malformed-test ()
  (let ((capture (hackmode-provider-wireless:parse-airodump-csv-file
                  (fixture-path "malformed.csv"))))
    (assert (null (hackmode-provider-wireless:airodump-capture-ap-rows capture))
            ()
            "short AP row does not become a record")
    (assert (null (hackmode-provider-wireless:airodump-capture-station-rows
                   capture)))
    (let ((issues (hackmode-provider-wireless:airodump-capture-parse-issues
                   capture)))
      (assert (= 3 (length issues)))
      (assert-equal :preamble
                    (hackmode-provider-wireless:airodump-parse-issue-section
                     (first issues)))
      (assert-equal :ap
                    (hackmode-provider-wireless:airodump-parse-issue-section
                     (second issues)))
      (assert-equal :station
                    (hackmode-provider-wireless:airodump-parse-issue-section
                     (third issues)))
      (dolist (issue issues)
        (assert (plusp (length
                        (hackmode-provider-wireless:airodump-parse-issue-raw
                         issue)))
                ()
                "malformed rows keep their raw text")
        (assert (plusp (length
                        (hackmode-provider-wireless:airodump-parse-issue-reason
                         issue)))
                ()
                "malformed rows carry a reason")))))

(defun run-network-doc-test ()
  (let* ((capture (hackmode-provider-wireless:parse-airodump-csv-file
                   (fixture-path "multi.csv")))
         (rows (hackmode-provider-wireless:airodump-capture-ap-rows capture))
         (counts (hackmode-provider-wireless:capture-client-counts capture))
         (doc (hackmode-provider-wireless:airodump-row->wireless-network-doc
               (first rows)
               :capture-id "multi"
               :client-count (gethash "aa:bb:cc:dd:ee:ff" counts)))
         (data (jsown:val doc "data")))
    (assert-equal (hackmode-provider-wireless:wireless-network-id
                   "AA:BB:CC:DD:EE:FF" "HomeNet" "airodump-ng:multi")
                  (jsown:val doc "_id")
                  "network doc deterministic id")
    (assert-equal "wireless-network" (jsown:val doc "dtype"))
    (assert-equal "airodump-ng" (jsown:val doc "dataset"))
    (assert-equal "0.9.0" (jsown:val doc "schema_version"))
    (assert-equal 1 (jsown:val doc "version"))
    (assert-equal "2026-09-20T09:00:00Z" (jsown:val doc "date_added")
                  "date_added from row first-seen (UTC interpretation)")
    (assert-equal "2026-09-20T09:05:00Z" (jsown:val doc "date_updated"))
    (assert-equal "aa:bb:cc:dd:ee:ff" (jsown:val-safe data "bssid"))
    (assert-equal "HomeNet" (jsown:val-safe data "ssid"))
    (assert-equal "wpa2-psk" (jsown:val-safe data "security"))
    (assert-equal "CCMP" (jsown:val-safe data "cipher_suite"))
    (assert-equal "PSK" (jsown:val-safe data "auth_mode"))
    (assert-equal 6 (jsown:val-safe data "channel"))
    (assert-equal "2.4ghz" (jsown:val-safe data "band"))
    (assert-equal 2437 (jsown:val-safe data "frequency_mhz"))
    (assert-equal -50 (jsown:val-safe data "signal_dbm"))
    (assert-equal 120 (jsown:val-safe data "observations"))
    (assert-equal 2 (jsown:val-safe data "client_count"))
    (assert-equal "2026-09-20T09:00:00Z" (jsown:val-safe data "first_seen"))
    (assert-equal "2026-09-20T09:05:00Z" (jsown:val-safe data "last_seen"))
    (assert-equal "airodump-ng:multi" (jsown:val-safe data "source_network_id"))
    ;; -1 power omits signal_dbm
    (let ((doc4 (hackmode-provider-wireless:airodump-row->wireless-network-doc
                 (fourth rows) :capture-id "multi")))
      (assert (null (jsown:val-safe (jsown:val doc4 "data") "signal_dbm"))
              ()
              "-1 power sentinel omits signal_dbm"))
    ;; evidence: lossless raw row + deterministic hash
    (let ((evidence (first (jsown:val doc "evidence"))))
      (assert-equal (hackmode-provider-wireless:airodump-ap-row-raw (first rows))
                    (jsown:val evidence "excerpt")
                    "raw row carried verbatim in evidence")
      (assert-equal "sha256" (jsown:val evidence "hash_algorithm"))
      (assert-equal (hackmode-provider-wireless:identity-digest
                     (list (hackmode-provider-wireless:airodump-ap-row-raw
                            (first rows))))
                    (jsown:val evidence "content_hash")))
    ;; sources
    (let ((source (first (jsown:val doc "sources"))))
      (assert-equal "sensor" (jsown:val source "kind"))
      (assert-equal "airodump-ng" (jsown:val source "name"))
      (assert-equal "local-csv" (jsown:val source "access_method")))))

(defun run-station-doc-test ()
  (let* ((capture (hackmode-provider-wireless:parse-airodump-csv-file
                   (fixture-path "multi.csv")))
         (rows (hackmode-provider-wireless:airodump-capture-station-rows capture))
         (doc (hackmode-provider-wireless:station-row->wireless-station-doc
               (fourth rows) :capture-id "multi"))
         (data (jsown:val doc "data")))
    (assert-equal (hackmode-provider-wireless:wireless-station-id
                   "DD:00:11:22:33:47" "multi")
                  (jsown:val doc "_id")
                  "station doc deterministic id")
    (assert-equal "wireless-station" (jsown:val doc "dtype"))
    (assert-equal "dd:00:11:22:33:47" (jsown:val-safe data "mac"))
    (assert-equal "station" (jsown:val-safe data "station_type"))
    (assert-equal "multi" (jsown:val-safe data "source_device_id"))
    (assert-equal '("HomeNet") (jsown:val-safe data "probe_ssids"))
    (assert (null (jsown:val-safe data "last_bssid"))
            ()
            "not-associated marker omits last_bssid")
    (assert (null (jsown:val-safe data "signal_dbm"))
            ()
            "-1 station power omits signal_dbm")
    (assert-equal 3 (jsown:val-safe data "packets"))
    (assert-equal "2026-09-20T09:02:00Z" (jsown:val-safe data "first_seen"))
    (let ((associated (hackmode-provider-wireless:station-row->wireless-station-doc
                       (first rows) :capture-id "multi")))
      (assert-equal "aa:bb:cc:dd:ee:ff"
                    (jsown:val-safe (jsown:val associated "data") "last_bssid")
                    "associated station keeps last_bssid")
      (assert-equal -60
                    (jsown:val-safe (jsown:val associated "data") "signal_dbm")))))

(defun run-enqueue-test ()
  (let* ((root (fresh-test-path))
         (db (tek9:new-database "operation" :path root))
         (hackmode:*asset-event-hook*
           (make-instance 'nhooks:hook-any :handlers nil)))
    (unwind-protect
         (progn
           (tek9:open-database db)
           (let* ((capture (hackmode-provider-wireless:parse-airodump-csv-file
                            (fixture-path "multi.csv"))))
             (multiple-value-bind (entries created)
                 (hackmode-provider-wireless:enqueue-airodump-observations
                  capture db :operation "wireless-capture" :source-id "multi.csv")
               (declare (ignore entries))
               (assert (= 8 created))
               (let ((outbox (hackmode:list-outbox-entries db)))
                 (assert (= 8 (length outbox)))
                 (let ((networks (remove "wireless-network" outbox
                                         :test (lambda (want entry)
                                                 (declare (ignore want))
                                                 (string/= "wireless-network"
                                                           (hackmode:outbox-entry-dtype
                                                            entry))))))
                   (assert (= 4 (length networks))
                           ()
                           "four wireless-network outbox entries"))
                 (let ((stations (remove "wireless-station" outbox
                                         :test (lambda (want entry)
                                                 (declare (ignore want))
                                                 (string/= "wireless-station"
                                                           (hackmode:outbox-entry-dtype
                                                            entry))))))
                   (assert (= 4 (length stations))
                           ()
                           "four wireless-station outbox entries"))
                 (dolist (entry outbox)
                   (assert (eq :queued (hackmode:outbox-entry-state entry)))
                   (assert-equal "wireless-capture"
                                 (hackmode:outbox-entry-operation entry)
                                 "operation propagated to outbox")
                   (assert (search "starintel:wireless-"
                                   (hackmode:outbox-entry-payload entry)))
                   (assert (search "\"schema_version\":\"0.9.0\""
                                   (hackmode:outbox-entry-payload entry)))))))
           ;; determinism: re-parse + re-enqueue collapses onto the same
           ;; byte-identical payloads, creating nothing
           (let ((again (hackmode-provider-wireless:parse-airodump-csv-file
                         (fixture-path "multi.csv"))))
             (multiple-value-bind (entries created)
                 (hackmode-provider-wireless:enqueue-airodump-observations
                  again db :operation "wireless-capture" :source-id "multi.csv")
               (declare (ignore entries))
               (assert (zerop created)
                       ()
                       "re-enqueue of identical capture creates no new entries")
               (assert (= 8 (length (hackmode:list-outbox-entries db)))
                       ()
                       "outbox does not grow on re-enqueue"))))
      (when (tek9:db-is-open-p db)
        (tek9:close-database db))
      (remove-test-path root))))

(defun run-airmon-test ()
  (let ((status-output
         (format nil "Found 2 processes that could cause trouble.~2%~
                      PHY~CInterface~CDriver~CChipset~2%~
                      phy0~Cwlan0~Cath9k~CQualcomm Atheros AR9280~%~
                      phy1~Cwlan1~Crt2800usb~CRalink Technology, Corp. RT2870/RT3070~%"
                 #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab))
        (start-output
         (format nil "~2%PHY~CInterface~CDriver~CChipset~2%~
                      (mac80211 monitor mode vif enabled for [phy0]wlan0 on [phy0]wlan0mon)~%"
                 #\Tab #\Tab #\Tab))
        (stop-output
         (format nil "~2%(monitor mode disabled)~%")))
    ;; status
    (multiple-value-bind (interfaces issues)
        (hackmode-provider-wireless:airmon-ng-status
         :runner (lambda (program args)
                   (declare (ignore program args))
                   (values status-output "" 0)))
      (declare (ignore issues))
      (assert-equal 2 (length interfaces))
      (let ((first (first interfaces)))
        (assert-equal "phy0" (getf first :phy))
        (assert-equal "wlan0" (getf first :interface))
        (assert-equal "ath9k" (getf first :driver))
        (assert-equal "Qualcomm Atheros AR9280" (getf first :chipset))))
    ;; start
    (let ((result (hackmode-provider-wireless:airmon-ng-start
                   "wlan0"
                   :runner (lambda (program args)
                             (declare (ignore program))
                             (assert-equal '("start" "wlan0") args)
                             (values start-output "" 0)))))
      (assert-equal "wlan0mon" (getf result :monitor-interface)))
    ;; stop
    (let ((result (hackmode-provider-wireless:airmon-ng-stop
                   "wlan0mon"
                   :runner (lambda (program args)
                             (declare (ignore program))
                             (assert-equal '("stop" "wlan0mon") args)
                             (values stop-output "" 0)))))
      (assert (getf result :stopped-p)))
    ;; failure containment
    (assert
      (handler-case
          (hackmode-provider-wireless:airmon-ng-status
           :runner (lambda (program args)
                     (declare (ignore program args))
                     (values "" "airmon-ng: wireless tools missing" 1)))
        (hackmode-provider-wireless:aircrack-command-failed (condition)
          (and (= 1 (hackmode-provider-wireless:aircrack-command-failed-exit-code
                     condition))
               (search "missing"
                       (hackmode-provider-wireless:aircrack-command-failed-output
                        condition))))
        (t () nil)))))

(defun run-airmon-guard-test ()
  ;; binary-presence guard on the default runner path
  (assert
    (handler-case
        (progn
          (hackmode-provider-wireless:ensure-tool-available
           "hackmode-no-such-tool-xyz")
          nil)
      (hackmode-provider-wireless:aircrack-tool-unavailable (condition)
        (equal "hackmode-no-such-tool-xyz"
               (hackmode-provider-wireless:aircrack-tool-unavailable-program
                condition)))))
  ;; airdump-ng default runner refuses unbounded captures before any
  ;; binary lookup
  (assert
    (handler-case
        (progn
          (hackmode-provider-wireless:run-airodump
           "wlan0" :runner #'hackmode-provider-wireless:airodump-process-runner)
          nil)
      (error (condition)
        (search "DURATION-SECONDS" (format nil "~a" condition))))))

(defun run-airodump-test ()
  (let* ((saw-argv '())
         (prefix (merge-pathnames "hackmode-airodump-test/capture"
                                  (uiop:temporary-directory)))
         (csv-path
           (hackmode-provider-wireless:run-airodump
            "wlan0mon"
            :channels '("1" "6" "11")
            :output-prefix prefix
            :duration-seconds 1
            :runner (lambda (program argv &key timeout-seconds)
                      (declare (ignore program timeout-seconds))
                      (push argv saw-argv)
                      (assert (equal "1,6,11"
                                     (nth (+ 1 (position "-c" argv :test #'string=))
                                          argv)))
                      (let ((target (parse-namestring
                                     (format nil "~a-01.csv"
                                             (namestring prefix)))))
                        (ensure-directories-exist target)
                        (uiop:copy-file (fixture-path "no-stations.csv") target))
                      (values "" "" 0)))))
    (assert (plusp (length saw-argv)))
    (let ((argv (first saw-argv)))
      (assert (member "-w" argv :test #'string=))
      (assert (member "--output-format" argv :test #'string=))
      (assert (member "csv" argv :test #'string=))
      (assert (member "wlan0mon" argv :test #'string=))
      (assert-equal "wlan0mon" (first (last argv)) "interface is the final argv element"))
    (assert (uiop:file-pathname-p csv-path))
    (assert (search "hackmode-airodump-test/capture-01.csv"
                    (namestring csv-path)))
    ;; missing CSV surfaces a clear error with stderr context
    (assert
      (handler-case
          (progn
            (hackmode-provider-wireless:run-airodump
             "wlan0mon"
             :output-prefix (merge-pathnames "hackmode-airodump-missing/"
                                             (uiop:temporary-directory))
             :duration-seconds 1
             :runner (lambda (program argv &key timeout-seconds)
                       (declare (ignore program argv timeout-seconds))
                       (values "" "airodump-ng: no such device" 0)))
            nil)
        (hackmode-provider-wireless:aircrack-command-failed (condition)
          (search "no such device"
                  (hackmode-provider-wireless:aircrack-command-failed-output
                   condition)))))
    (uiop:delete-directory-tree
     (merge-pathnames "hackmode-airodump-test/" (uiop:temporary-directory))
     :validate t :if-does-not-exist :ignore)))

(defun run-tests ()
  (run-identity-test)
  (run-parser-multi-test)
  (run-hidden-test)
  (run-security-matrix-test)
  (run-comma-essid-test)
  (run-crlf-test)
  (run-no-stations-test)
  (run-malformed-test)
  (run-network-doc-test)
  (run-station-doc-test)
  (run-enqueue-test)
  (run-airmon-test)
  (run-airmon-guard-test)
  (run-airodump-test)
  (format t "Hackmode wireless provider tests passed.~%")
  t)
