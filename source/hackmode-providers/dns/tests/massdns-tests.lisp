(defpackage :hackmode-provider-dns-tests
  (:use :cl)
  (:export :run-tests))

(in-package :hackmode-provider-dns-tests)

(defun assert-equal (expected actual &optional (label "values"))
  (assert (equal expected actual) ()
          "Expected ~a to be ~s, got ~s" label expected actual))

(defun fresh-test-path ()
  (merge-pathnames
   (format nil "hackmode-provider-dns-~a/" (tek9:make-key-id))
   (uiop:temporary-directory)))

(defun remove-test-path (path)
  (ignore-errors
    (uiop:delete-directory-tree path :validate t :if-does-not-exist :ignore)))

(defun massdns-fixture-output ()
  (format nil
          "{\"name\":\"www.example.com.\",\"type\":\"A\",\"class\":\"IN\",\"status\":\"NOERROR\",\"data\":{\"answers\":[{\"ttl\":60,\"type\":\"A\",\"class\":\"IN\",\"name\":\"www.example.com.\",\"data\":\"93.184.216.34\"}]}}~%{\"name\":\"missing.example.com.\",\"type\":\"A\",\"class\":\"IN\",\"status\":\"NXDOMAIN\",\"data\":{\"answers\":[]}}~%"))

(defun run-parser-test ()
  (let ((assets (hackmode-provider-dns:parse-massdns-output
                 (massdns-fixture-output))))
    (assert (= 1 (length assets)))
    (let ((asset (first assets)))
      (assert (typep asset 'hackmode:domain))
      (assert-equal "www.example.com"
                    (hackmode:domain-name asset)
                    "normalized MassDNS name")
      (assert-equal "A" (hackmode:domain-type asset) "MassDNS record type")
      (assert-equal '("93.184.216.34")
                    (hackmode:domain-ips asset)
                    "MassDNS resolved addresses"))))

(defun run-provider-test ()
  (let* ((root (fresh-test-path))
         (db (tek9:new-database "operation" :path root))
         (events 0)
         (hackmode:*asset-event-hook*
           (make-instance 'nhooks:hook-any :handlers nil)))
    (unwind-protect
         (progn
           (tek9:open-database db)
           (hackmode:clear-capability-providers)
           (hackmode:subscribe-asset-events
            (lambda (event)
              (let* ((asset (hackmode:asset-event-asset event))
                     (persisted (tek9:fetch* db (hackmode:doc-id asset))))
                (assert persisted ()
                        "DNS provider published before canonical persistence."))
              (incf events)))
           (hackmode-provider-dns:register-massdns-provider
            :runner (lambda (domain)
                      (declare (ignore domain))
                      (massdns-fixture-output)))
           (let* ((input (make-instance 'hackmode:domain
                                        :record "www.example.com"
                                        :record-type "A"))
                  (first (hackmode:run-capability
                          :dns-resolve input
                          :provider :massdns
                          :database db))
                  (repeat (hackmode:run-capability
                           :dns-resolve input
                           :provider :massdns
                           :database db)))
             (assert (eq :succeeded (hackmode:provider-job-result-state first)))
             (assert (= 1 (hackmode:provider-job-result-created-count first)))
             (assert (= 0 (hackmode:provider-job-result-created-count repeat)))
             (assert-equal (hackmode:provider-job-result-id first)
                           (hackmode:provider-job-result-id repeat)
                           "repeated DNS job identity")
             (assert (= 1 events))
             (assert (= 1 (length (hackmode:query-assets
                                   :database db :type :domain)))))

           ;; Backend failure is contained as an observable provider result.
           (hackmode-provider-dns:register-massdns-provider
            :runner (lambda (domain)
                      (declare (ignore domain))
                      (error "massdns unavailable")))
           (let ((failed
                   (hackmode:run-capability
                    :dns-resolve
                    (make-instance 'hackmode:domain
                                   :record "failure.example"
                                   :record-type "A")
                    :provider :massdns
                    :database db)))
             (assert (eq :failed (hackmode:provider-job-result-state failed)))
             (assert (search "massdns unavailable"
                             (hackmode:provider-job-result-error failed)))))
      (hackmode:clear-capability-providers)
      (when (tek9:db-is-open-p db)
        (tek9:close-database db))
      (remove-test-path root))))

(defun run-tests ()
  (run-parser-test)
  (run-provider-test)
  (format t "Hackmode DNS provider tests passed.~%")
  t)
