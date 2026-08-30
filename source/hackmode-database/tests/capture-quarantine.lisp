(in-package :hackmode-database-tests)

(defun run-capture-quarantine-tests ()
  (let* ((record (hackmode-database:make-capture-quarantine-record
                  :operation-id "op-capture"
                  :capture-session-id "capture-1"
                  :source-id "spool-a"
                  :offset 256
                  :length 48
                  :reason "truncated-frame"
                  :raw-evidence-ref "spool-a#256+48"
                  :framing-version "ipx/1"
                  :provenance '(:parser "ipx-http/1")))
         (same (hackmode-database:make-capture-quarantine-record
                :operation-id "op-capture"
                :capture-session-id "capture-1"
                :source-id "spool-a"
                :offset 256
                :length 48
                :reason "truncated-frame"
                :raw-evidence-ref "spool-a#256+48"
                :framing-version "ipx/1"
                :provenance '(:parser "ipx-http/1"))))
    (ensure (eq :capture-quarantine
                (hackmode-database:execution-record-kind record))
            "capture quarantine has wrong execution kind")
    (ensure (string= (hackmode-database:execution-record-record-id record)
                     (hackmode-database:execution-record-record-id same))
            "identical quarantine replay changed stable identity")
    (let* ((path (merge-pathnames
                  (format nil "hackmode-capture-quarantine-~D/" (random 1000000000))
                  (uiop:temporary-directory)))
           (database (tek9:new-database "hackmode-capture-quarantine-test" :path path)))
      (unwind-protect
           (progn
             (tek9:open-database database)
             (hackmode-database:persist-execution-record database record)
             (hackmode-database:persist-execution-record database same)
             (let ((records (hackmode-database:fetch-capture-quarantine-records
                             database "op-capture" "capture-1" "spool-a")))
               (ensure (= 1 (length records)) "quarantine replay duplicated evidence")
               (ensure (= 256 (getf (hackmode-database:execution-record-payload
                                      (first records)) :offset))
                       "quarantine offset was not retained")))
        (when (tek9:db-is-open-p database) (tek9:close-database database))
        (when (probe-file path) (uiop:delete-directory-tree path :validate t))))
    (handler-case
        (progn
          (hackmode-database:make-capture-quarantine-record
           :operation-id "op-capture" :capture-session-id "capture-1"
           :source-id "spool-a" :offset -1 :length 1 :reason "corrupt"
           :raw-evidence-ref "ref" :framing-version "ipx/1"
           :provenance '(:parser "ipx-http/1"))
          (error "negative quarantine offset unexpectedly accepted"))
      (hackmode-database:execution-graph-validation-error () t))
    (handler-case
        (progn
          (hackmode-database:make-capture-quarantine-record
           :operation-id "op-capture" :capture-session-id "capture-1"
           :source-id "spool-a" :offset 1 :length 0 :reason ""
           :raw-evidence-ref "ref" :framing-version "ipx/1"
           :provenance '(:parser "ipx-http/1"))
          (error "empty quarantine reason unexpectedly accepted"))
      (hackmode-database:execution-graph-validation-error () t)))
  t)
