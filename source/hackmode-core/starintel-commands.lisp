;;;; Interactive LISH commands for the StarIntel integration.
;;;
;;; hackmode.asd deliberately does not depend on LISH; this file loads only
;;; through the optional :HACKMODE-STARINTEL-COMMANDS system so the core and
;;; its tests stay loadable without it.
(in-package :hackmode)

(lish:defcommand starintel-flush ()
  "Drain the durable StarIntel outbox to the configured server."
  (print-starintel-sync-report (starintel-sync)))

(lish:defcommand starintel-outbox ((state string :optional t
                                             :help "Filter by state: queued sending retry quarantined failed acknowledged"))
  "Summarize the durable StarIntel outbox."
  (multiple-value-bind (counts entries)
      (starintel-outbox-status
       :state (when (and state (plusp (length state)))
                (read-from-string (format nil ":~a" state))))
    (format t "StarIntel outbox:~{ ~a=~a~}~%" counts)
    (loop for entry in entries
          do (format t "~a ~a ~a attempts=~a~%"
                     (outbox-entry-state entry)
                     (outbox-entry-dtype entry)
                     (outbox-entry-document-id entry)
                     (outbox-entry-attempts entry)))))

(lish:defcommand starintel-get ((id string :help "StarIntel document id."))
  "Fetch and print one StarIntel document."
  (let ((document (starintel-get-document (make-starintel-client) id)))
    (if (and (listp document) (not (keywordp document)))
        (format t "~a~%" (jsown:to-json document))
        (format t "starintel-get: ~a~%" document))))

(lish:defcommand starintel-search ((query string :help "FTS query string.")
                                   (limit integer :optional t :default 20
                                                     :help "Maximum results per page."))
  "Search StarIntel documents and print matching ids."
  (multiple-value-bind (documents bookmark)
      (starintel-search (make-starintel-client) query :limit limit)
    (if (listp documents)
        (progn
          (loop for document in documents
                do (format t "~a~%" (jsown:val-safe document "_id")))
          (when bookmark
            (format t "bookmark: ~a~%" bookmark)))
        (format t "starintel-search: ~a~%" documents))))
