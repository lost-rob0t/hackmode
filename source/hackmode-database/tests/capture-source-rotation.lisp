(in-package :hackmode-database-tests)

(defun run-capture-source-rotation-tests ()
  (let* ((first
           (make-capture-source-rotation-record
            :operation-id "op-rotation"
            :capture-session-id "capture-1"
            :previous-source-id "capture.log"
            :next-source-id "capture.log.1"
            :previous-final-offset 4096
            :framing-version "ipx/1"
            :provenance '(:parser "fixture" :version "1")))
         (same
           (make-capture-source-rotation-record
            :operation-id "op-rotation"
            :capture-session-id "capture-1"
            :previous-source-id "capture.log"
            :next-source-id "capture.log.1"
            :previous-final-offset 4096
            :framing-version "ipx/1"
            :provenance '(:parser "fixture" :version "1"))))
    (ensure (eq :capture-source-rotation (execution-record-kind first))
            "capture source rotation has wrong execution kind")
    (ensure (string= "capture-1" (execution-record-run-id first))
            "capture source rotation lost capture-session identity")
    (ensure (string= "capture.log.1" (execution-record-call-id first))
            "capture source rotation lost successor source identity")
    (ensure (string= (execution-record-record-id first)
                     (execution-record-record-id same))
            "identical capture source rotation replay changed identity")
    (ensure (equal '(:previous-source-id "capture.log"
                     :next-source-id "capture.log.1"
                     :previous-final-offset 4096
                     :framing-version "ipx/1")
                   (execution-record-payload first))
            "capture source rotation payload drifted")
    (let ((roundtrip
            (tek9-node->execution-record
             (execution-record->tek9-node first))))
      (ensure (eq :capture-source-rotation (execution-record-kind roundtrip))
              "capture source rotation round-trip lost kind")
      (ensure (equal (execution-record-payload first)
                     (execution-record-payload roundtrip))
              "capture source rotation round-trip lost lineage payload"))
    (handler-case
        (progn
          (make-capture-source-rotation-record
           :operation-id "op-rotation"
           :capture-session-id "capture-1"
           :previous-source-id "capture.log"
           :next-source-id "capture.log"
           :previous-final-offset 4096
           :framing-version "ipx/1"
           :provenance '(:parser "fixture"))
          (error "self-rotation unexpectedly accepted"))
      (execution-graph-validation-error () t)))

  (let* ((path (merge-pathnames
                (format nil "hackmode-capture-rotation-~D/"
                        (random 1000000000))
                (uiop:temporary-directory)))
         (database (tek9:new-database "hackmode-capture-rotation-test" :path path)))
    (unwind-protect
         (progn
           (tek9:open-database database)
           (let ((rotation-a
                   (make-capture-source-rotation-record
                    :operation-id "op-rotation"
                    :capture-session-id "capture-1"
                    :previous-source-id "capture.log"
                    :next-source-id "capture.log.1"
                    :previous-final-offset 4096
                    :framing-version "ipx/1"
                    :provenance '(:parser "fixture")))
                 (rotation-b
                   (make-capture-source-rotation-record
                    :operation-id "op-rotation"
                    :capture-session-id "capture-1"
                    :previous-source-id "capture.log.1"
                    :next-source-id "capture.log.2"
                    :previous-final-offset 8192
                    :framing-version "ipx/1"
                    :provenance '(:parser "fixture")))
                 (fork
                   (make-capture-source-rotation-record
                    :operation-id "op-rotation"
                    :capture-session-id "capture-1"
                    :previous-source-id "capture.log"
                    :next-source-id "capture.log.alt"
                    :previous-final-offset 4096
                    :framing-version "ipx/1"
                    :provenance '(:parser "fixture")))
                 (foreign
                   (make-capture-source-rotation-record
                    :operation-id "op-other"
                    :capture-session-id "capture-1"
                    :previous-source-id "other.log"
                    :next-source-id "other.log.1"
                    :previous-final-offset 1024
                    :framing-version "ipx/1"
                    :provenance '(:parser "fixture"))))
             (persist-execution-record database rotation-b)
             (persist-execution-record database rotation-a)
             (persist-execution-record database rotation-a)
             (handler-case
                 (progn
                   (persist-execution-record database fork)
                   (error "divergent capture source rotation fork unexpectedly persisted"))
               (persistence-replay-conflict () t))
             (persist-execution-record database foreign)
             (let ((rotations
                     (fetch-capture-source-rotations
                      database "op-rotation" "capture-1")))
               (ensure (= 2 (length rotations))
                       "capture source rotation replay duplicated lineage")
               (ensure (equal '(4096 8192)
                              (mapcar
                               (lambda (record)
                                 (getf (execution-record-payload record)
                                       :previous-final-offset))
                               rotations))
                       "capture source rotations are not returned in durable offset order")
               (ensure (every
                        (lambda (record)
                          (string= "op-rotation"
                                   (execution-record-operation-id record)))
                        rotations)
                       "capture source rotation query leaked another operation"))))
      (when (tek9:db-is-open-p database)
        (tek9:close-database database))
      (when (probe-file path)
        (uiop:delete-directory-tree path :validate t))))
  t)
