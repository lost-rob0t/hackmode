(uiop:define-package :hackmode-database-tests
  (:use :cl :hackmode-database)
  (:export #:run-tests))

(in-package :hackmode-database-tests)

(defun run-asset-containment-tests ()
  (let* ((path (merge-pathnames
                (format nil "hackmode-containment-~D/" (random 1000000000))
                (uiop:temporary-directory)))
         (database (tek9:new-database "hackmode-containment-test" :path path)))
    (unwind-protect
         (progn
           (tek9:open-database database)
           (let ((record (make-asset-containment-record
                          :operation-id "op-contain"
                          :child-id "asset-input-1"
                          :parent-id "asset-url-1")))
             ;; Validation: empty fields fail closed.
             (ensure (not (ignore-errors
                           (make-asset-containment-record
                            :operation-id "" :child-id "c" :parent-id "p")))
                     "empty operation-id must be rejected")
             (ensure (not (ignore-errors
                           (make-asset-containment-record
                            :operation-id "o" :child-id "" :parent-id "p")))
                     "empty child-id must be rejected")
             ;; Round trip.
             (persist-asset-containment database record)
             (let ((rows (fetch-asset-containment database "op-contain")))
               (ensure (= 1 (length rows))
                       "expected exactly one containment row")
               (ensure (string= "asset-input-1"
                                (asset-containment-record-child-id
                                 (first rows)))
                       "child identity lost")
               (ensure (string= "asset-url-1"
                                (asset-containment-record-parent-id
                                 (first rows)))
                       "parent identity lost"))
             ;; Replay of the identical record is idempotent.
             (persist-asset-containment database record)
             (ensure (= 1 (length (fetch-asset-containment database "op-contain")))
                     "identical replay must not duplicate rows")
             ;; A second distinct child sorts deterministically.
             (persist-asset-containment
              database
              (make-asset-containment-record
               :operation-id "op-contain"
               :child-id "asset-input-0"
               :parent-id "asset-url-1"))
             (let ((rows (fetch-asset-containment database "op-contain")))
               (ensure (equal '("asset-input-0" "asset-input-1")
                              (mapcar #'asset-containment-record-child-id rows))
                       "containment rows must sort by child id"))
             ;; Operation scoping: another operation sees nothing.
             (ensure (null (fetch-asset-containment database "op-other"))
                     "containment must be operation-scoped")))
      (when (tek9:db-is-open-p database)
        (tek9:close-database database))
      (when (probe-file path)
        (uiop:delete-directory-tree path :validate t))))
  t)
