(in-package :hackmode-database-tests)

(defun run-capture-checkpoint-tests ()
  (let* ((first (hackmode-database:make-capture-checkpoint-record
                 :operation-id "op-capture"
                 :capture-session-id "capture-1"
                 :source-id "spool-a"
                 :offset 128
                 :last-record-id "exchange-1"
                 :framing-version "ipx/1"
                 :provenance '(:parser "ipx-http/1")))
         (same (hackmode-database:make-capture-checkpoint-record
                :operation-id "op-capture"
                :capture-session-id "capture-1"
                :source-id "spool-a"
                :offset 128
                :last-record-id "exchange-1"
                :framing-version "ipx/1"
                :provenance '(:parser "ipx-http/1")))
         (later (hackmode-database:make-capture-checkpoint-record
                 :operation-id "op-capture"
                 :capture-session-id "capture-1"
                 :source-id "spool-a"
                 :offset 512
                 :last-record-id "exchange-2"
                 :framing-version "ipx/1"
                 :provenance '(:parser "ipx-http/1"))))
    (ensure (eq :capture-checkpoint
                (hackmode-database:execution-record-kind first))
            "capture checkpoint has wrong execution kind")
    (ensure (string= "capture-1"
                     (hackmode-database:execution-record-run-id first))
            "capture session identity was not retained")
    (ensure (string= "spool-a"
                     (hackmode-database:execution-record-call-id first))
            "capture source identity was not retained")
    (ensure (string= (hackmode-database:execution-record-record-id first)
                     (hackmode-database:execution-record-record-id same))
            "identical checkpoint replay changed stable identity")
    (let* ((path (merge-pathnames
                  (format nil "hackmode-capture-checkpoint-~D/"
                          (random 1000000000))
                  (uiop:temporary-directory)))
           (database (tek9:new-database "hackmode-capture-checkpoint-test"
                                        :path path)))
      (unwind-protect
           (progn
             (tek9:open-database database)
             (hackmode-database:persist-execution-record database first)
             (hackmode-database:persist-execution-record database same)
             (hackmode-database:persist-execution-record database later)
             (let ((checkpoint
                     (hackmode-database:fetch-latest-capture-checkpoint
                      database "op-capture" "capture-1" "spool-a")))
               (ensure checkpoint "latest checkpoint was not found")
               (ensure (= 512
                          (getf (hackmode-database:execution-record-payload checkpoint)
                                :offset))
                       "latest checkpoint did not select greatest durable offset")
               (ensure (string= "exchange-2"
                                (getf (hackmode-database:execution-record-payload checkpoint)
                                      :last-record-id))
                       "latest checkpoint lost last-record evidence identity"))
             (ensure (null (hackmode-database:fetch-latest-capture-checkpoint
                            database "op-capture" "capture-1" "spool-missing"))
                     "checkpoint lookup leaked across capture sources"))
        (when (tek9:db-is-open-p database)
          (tek9:close-database database))
        (when (probe-file path)
          (uiop:delete-directory-tree path :validate t))))
    (handler-case
        (progn
          (hackmode-database:make-capture-checkpoint-record
           :operation-id "op-capture"
           :capture-session-id "capture-1"
           :source-id "spool-a"
           :offset -1
           :framing-version "ipx/1"
           :provenance '(:parser "ipx-http/1"))
          (error "negative checkpoint offset unexpectedly accepted"))
      (hackmode-database:execution-graph-validation-error () t))
    (handler-case
        (progn
          (hackmode-database:make-capture-checkpoint-record
           :operation-id "op-capture"
           :capture-session-id "capture-1"
           :source-id "spool-a"
           :offset 128
           :framing-version ""
           :provenance '(:parser "ipx-http/1"))
          (error "empty framing version unexpectedly accepted"))
      (hackmode-database:execution-graph-validation-error () t)))
  t)
