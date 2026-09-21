(uiop:define-package :hackmode-provider-wireless
  (:use :cl)
  (:nicknames :hackmode.providers.wireless)
  (:export
   ;; identity (Python parity with tools/wireless)
   :normalize-mac
   :normalize-ssid
   :identity-digest
   :deterministic-id
   :wireless-network-id
   :wireless-station-id
   ;; parsing
   :parse-airodump-csv
   :parse-airodump-csv-file
   :parse-airodump-csv-path
   :airodump-capture
   :airodump-capture-capture-id
   :airodump-capture-source-path
   :airodump-capture-ap-rows
   :airodump-capture-station-rows
   :airodump-capture-parse-issues
   :airodump-ap-row
   :airodump-ap-row-p
   :airodump-ap-row-raw
   :airodump-ap-row-bssid
   :airodump-ap-row-first-time-seen
   :airodump-ap-row-last-time-seen
   :airodump-ap-row-channel
   :airodump-ap-row-speed
   :airodump-ap-row-privacy
   :airodump-ap-row-cipher
   :airodump-ap-row-authentication
   :airodump-ap-row-power
   :airodump-ap-row-beacons
   :airodump-ap-row-ivs
   :airodump-ap-row-lan-ip
   :airodump-ap-row-id-length
   :airodump-ap-row-essid
   :airodump-ap-row-key
   :airodump-ap-row-essid-comma-recovered
   :airodump-station-row
   :airodump-station-row-p
   :airodump-station-row-raw
   :airodump-station-row-mac
   :airodump-station-row-first-time-seen
   :airodump-station-row-last-time-seen
   :airodump-station-row-power
   :airodump-station-row-packets
   :airodump-station-row-bssid
   :airodump-station-row-probed-essids
   :airodump-parse-issue
   :airodump-parse-issue-p
   :airodump-parse-issue-raw
   :airodump-parse-issue-section
   :airodump-parse-issue-reason
   ;; airmon-ng
   :*airmon-ng-program*
   :aircrack-tool-unavailable
   :aircrack-tool-unavailable-program
   :aircrack-command-failed
   :aircrack-command-failed-program
   :aircrack-command-failed-exit-code
   :aircrack-command-failed-output
   :shell-runner
   :ensure-tool-available
   :find-program-in-path
   :parse-airmon-interfaces
   :parse-airmon-monitor-interface
   :airmon-ng-status
   :airmon-ng-start
   :airmon-ng-stop
   ;; airodump-ng
   :*airodump-ng-program*
   :*airodump-poll-interval*
   :airodump-process-runner
   :run-airodump
   :capture-id-from-path
   :find-airodump-csv
   ;; projection
   :*wireless-dataset*
   :airodump-security
   :channel-band
   :channel-frequency-mhz
   :airodump-timestamp->iso
   :hidden-essid-p
   :airodump-row->wireless-network-doc
   :station-row->wireless-station-doc
   :capture-client-counts
   :capture-default-now
   :enqueue-airodump-observations))

(in-package :hackmode-provider-wireless)
