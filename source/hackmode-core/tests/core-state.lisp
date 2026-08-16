(defpackage :hackmode-tests
  (:use :cl))

(in-package :hackmode-tests)

(defun assert-equal (expected actual &optional (label "values"))
  (assert (equal expected actual) ()
          "Expected ~a to be ~s, got ~s" label expected actual))

(defun fresh-test-path (prefix)
  (merge-pathnames
   (format nil "~a-~a/" prefix (tek9:make-key-id))
   (uiop:temporary-directory)))

(defun remove-test-path (path)
  (ignore-errors
    (uiop:delete-directory-tree path :validate t :if-does-not-exist :ignore)))

(defun run-instance-state-test ()
  (let ((left (make-instance 'hackmode:domain
                             :record "left.example"
                             :tags '("left")))
        (right (make-instance 'hackmode:domain
                              :record "right.example"
                              :tags '("right")))
        (op-a (make-instance 'hackmode:operation :name "a" :dir "/tmp/a/"))
        (op-b (make-instance 'hackmode:operation :name "b" :dir "/tmp/b/")))
    (assert (not (string= (hackmode:doc-id left) (hackmode:doc-id right))))
    (setf (hackmode:doc-tags left) '("changed"))
    (assert-equal '("right") (hackmode:doc-tags right) "instance-local tags")
    (assert-equal "a" (hackmode:operation-name op-a) "operation A")
    (assert-equal "b" (hackmode:operation-name op-b) "operation B")))

(defun run-operation-registry-test ()
  (let* ((root (fresh-test-path "hackmode-operations"))
         (workspace (fresh-test-path "hackmode-workspace"))
         (hackmode:*operations-database*
           (tek9:new-database "operations" :path root)))
    (unwind-protect
         (progn
           (hackmode:new-operation "alpha" workspace "test operation")
           (assert-equal "alpha"
                         (hackmode:operation-name
                          (hackmode:select-operation "alpha"))
                         "selected operation")
           (tek9:close-database hackmode:*operations-database*)
           (hackmode:ensure-operations-database-open)
           (assert-equal '("alpha")
                         (mapcar #'hackmode:operation-name
                                 (hackmode:list-operations))
                         "reopened operation registry"))
      (when (tek9:db-is-open-p hackmode:*operations-database*)
        (tek9:close-database hackmode:*operations-database*))
      (remove-test-path root)
      (remove-test-path workspace))))

(defun run-asset-lifecycle-test ()
  (let* ((root (fresh-test-path "hackmode-assets"))
         (db (tek9:new-database "assets" :path root))
         (events 0)
         (hackmode:*asset-event-hook*
           (make-instance 'nhooks:hook-void :handlers nil)))
    (unwind-protect
         (progn
           (tek9:open-database db)
           (hackmode:subscribe-asset-events
            (lambda (event)
              (assert (eq :discovered
                          (hackmode:asset-event-event-type event)))
              (let* ((asset (hackmode:asset-event-asset event))
                     (persisted (tek9:fetch* db (hackmode:doc-id asset))))
                (assert persisted ()
                        "Asset event fired before local persistence."))
              (incf events)))
           (let ((first (make-instance 'hackmode:domain
                                       :record "Example.COM."
                                       :record-type "a"))
                 (second (make-instance 'hackmode:domain
                                        :record "example.com"
                                        :record-type "A")))
             (multiple-value-bind (stored created-p)
                 (hackmode:discover-asset first :database db)
               (assert created-p)
               (assert-equal "example.com" (hackmode:domain-name stored)
                             "normalized domain"))
             (multiple-value-bind (stored created-p)
                 (hackmode:discover-asset second :database db)
               (declare (ignore stored))
               (assert (not created-p)))
             (assert (= events 1))
             (assert (= 1 (length (hackmode:query-assets
                                   :database db
                                   :type :domain))))))
      (when (tek9:db-is-open-p db)
        (tek9:close-database db))
      (remove-test-path root))))

(defun run-tests ()
  (run-instance-state-test)
  (run-operation-registry-test)
  (run-asset-lifecycle-test)
  (format t "Hackmode core tests passed.~%")
  t)
