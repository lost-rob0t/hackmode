(defpackage :hackmode-provider-recon-tests
  (:use :cl)
  (:export :run-tests))

(in-package :hackmode-provider-recon-tests)

(defun assert-equal (expected actual &optional (label "values"))
  (assert (equal expected actual) ()
          "Expected ~a to be ~s, got ~s" label expected actual))

(defun fresh-test-path ()
  (merge-pathnames
   (format nil "hackmode-provider-recon-~a/" (tek9:make-key-id))
   (uiop:temporary-directory)))

(defun remove-test-path (path)
  (ignore-errors
    (uiop:delete-directory-tree path :validate t :if-does-not-exist :ignore)))

(defun run-subfinder-parser-test ()
  (let ((assets
          (hackmode-provider-recon:parse-subfinder-output
           (format nil
                   "WWW.Example.COM~%api.example.com~%*.wild.example.com~%outside.test~%api.example.com~%")
           "example.com")))
    (assert-equal '("www.example.com" "api.example.com" "wild.example.com")
                  (mapcar #'hackmode:domain-name assets)
                  "subfinder scoped domains")))

(defun run-crtsh-parser-test ()
  (let* ((json
           "[{\"name_value\":\"*.example.com\\napi.example.com\"},{\"name_value\":\"admin@example.com\"},{\"name_value\":\"outside.test\"}]")
         (assets
           (hackmode-provider-recon:parse-crtsh-response json "example.com")))
    (assert-equal '("example.com" "api.example.com")
                  (mapcar #'hackmode:domain-name assets)
                  "crt.sh scoped domains")))

(defun run-http-parser-test ()
  (let ((result
          (hackmode-provider-recon:parse-http-probe-output
           (format nil "200~Chttps://example.com/~Ctext/html~C93.184.216.34~C1~%"
                   #\Tab #\Tab #\Tab #\Tab))))
    (assert (= 200 (getf result :status)))
    (assert-equal "https://example.com/"
                  (getf result :effective-url)
                  "HTTP effective URL")
    (assert-equal "text/html"
                  (getf result :content-type)
                  "HTTP content type")
    (assert-equal "93.184.216.34"
                  (getf result :remote-ip)
                  "HTTP remote IP")
    (assert (= 1 (getf result :redirects)))))

(defun run-http-write-out-format-test ()
  (let ((value (hackmode-provider-recon::http-probe-write-out-format)))
    (assert (= 4 (count #\Tab value)))
    (assert (search "%{http_code}" value))
    (assert (search "%{url_effective}" value))))

(defun run-provider-test ()
  (let* ((root (fresh-test-path))
         (db (tek9:new-database "operation" :path root))
         (hackmode:*asset-event-hook*
           (make-instance 'nhooks:hook-any :handlers nil)))
    (unwind-protect
         (progn
           (tek9:open-database db)
           (hackmode:clear-capability-providers)

           (hackmode-provider-recon:register-subfinder-provider
            :runner
            (lambda (domain)
              (declare (ignore domain))
              (format nil "www.example.com~%api.example.com~%")))
           (hackmode-provider-recon:register-crtsh-provider
            :runner
            (lambda (domain)
              (declare (ignore domain))
              "[{\"name_value\":\"cert.example.com\"}]"))
           (hackmode-provider-recon:register-http-probe-provider
            :runner
            (lambda (url)
              (declare (ignore url))
              (format nil "200~Chttps://example.com/~Ctext/html~C93.184.216.34~C0~%"
                      #\Tab #\Tab #\Tab #\Tab)))

           (let* ((domain
                    (make-instance 'hackmode:domain
                                   :record "example.com"
                                   :record-type "A"))
                  (subdomains
                    (hackmode:run-capability
                     :subdomain-enumerate domain
                     :provider :subfinder
                     :database db))
                  (certificate-names
                    (hackmode:run-capability
                     :subdomain-enumerate domain
                     :provider :crtsh
                     :database db)))
             (assert (eq :succeeded
                         (hackmode:provider-job-result-state subdomains)))
             (assert (= 2
                        (hackmode:provider-job-result-created-count subdomains)))
             (assert (eq :succeeded
                         (hackmode:provider-job-result-state certificate-names)))
             (assert (= 1
                        (hackmode:provider-job-result-created-count
                         certificate-names))))

           (let* ((url
                    (make-instance 'hackmode:url
                                   :scheme "https"
                                   :host "example.com"
                                   :port 443
                                   :path "/"))
                  (probe
                    (hackmode:run-capability
                     :http-probe url
                     :provider :curl
                     :database db))
                  (asset (first (hackmode:provider-job-result-assets probe))))
             (assert (eq :succeeded
                         (hackmode:provider-job-result-state probe)))
             (assert (= 1 (hackmode:provider-job-result-created-count probe)))
             (assert (typep asset 'hackmode:finding))
             (assert-equal "http-observation"
                           (hackmode:finding-finding-type asset)
                           "HTTP finding type")
             (assert (search "status=200"
                             (hackmode:finding-data asset))))

           (let ((providers
                   (hackmode:list-capability-providers
                    :subdomain-enumerate)))
             (assert-equal '("subfinder" "crtsh")
                           (mapcar #'hackmode:capability-provider-name providers)
                           "provider priority order")))
      (hackmode:clear-capability-providers)
      (when (tek9:db-is-open-p db)
        (tek9:close-database db))
      (remove-test-path root))))

(defun run-tests ()
  (run-subfinder-parser-test)
  (run-crtsh-parser-test)
  (run-http-parser-test)
  (run-http-write-out-format-test)
  (run-provider-test)
  (format t "Hackmode recon provider tests passed.~%")
  t)
