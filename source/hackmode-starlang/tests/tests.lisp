(defpackage :hackmode-starlang-tests
  (:use :cl)
  (:export :run-tests))

(in-package :hackmode-starlang-tests)

(defun assert-equal (expected actual &optional (label "values"))
  (assert (equal expected actual) ()
          "Expected ~a to be ~s, got ~s" label expected actual))

(defun fresh-test-path ()
  (merge-pathnames
   (format nil "hackmode-starlang-~a/" (tek9:make-key-id))
   (uiop:temporary-directory)))

(defun remove-test-path (path)
  (ignore-errors
   (uiop:delete-directory-tree path :validate t :if-does-not-exist :ignore)))

(defun run-spec-library-test ()
  (let ((graph (hackmode-starlang:load-pentest-graph :reload t)))
    (assert graph)
    (assert-equal "org.hackmode/pentest@1"
                  (hackmode-starlang:pentest-library-name)
                  "pentest library identity")
    (assert-equal '("subfinder" "crtsh" "massdns" "nmap" "httpx" "katana")
                  (hackmode-starlang:declared-recon-tools)
                  "declared recon tools")
    (assert-equal '("nuclei" "zap")
                  (hackmode-starlang:declared-vuln-tools)
                  "declared vuln tools")
    (assert-equal '("subfinder" "crtsh" "massdns" "nmap" "httpx" "katana"
                    "nuclei" "zap")
                  (hackmode-starlang:declared-tools)
                  "declared tool catalog")
    (assert-equal '("runId" "kind" "tool" "target" "argv" "status"
                    "exitCode" "stdout" "stderr" "raw")
                  (hackmode-starlang:pentest-declaration-fields
                   :document "tool-run")
                  "tool-run wire fields")
    (assert-equal '("runId" "tool" "target" "templateId" "severity" "host"
                    "matchedAt" "evidence" "raw")
                  (hackmode-starlang:pentest-declaration-fields
                   :document "vuln-finding")
                  "vuln-finding wire fields")
    (assert-equal '("runId" "tool" "target" "options")
                  (hackmode-starlang:pentest-declaration-fields
                   :message "run-vuln-scan")
                  "run-vuln-scan message fields")
    (assert-equal :recon (hackmode-starlang:tool-kind-for "subfinder"))
    (assert-equal :vuln (hackmode-starlang:tool-kind-for "nuclei"))))

(defun run-tool-run-document-test ()
  (let* ((document
           (hackmode-starlang:make-tool-run-document
            "run-1" :recon "subfinder" "example.com"
            '("subfinder" "-silent" "-d" "example.com")
            :completed
            :exit-code 0
            :stdout "www.example.com"
            :stderr ""
            :raw '((:origin . "hackmode-starlang-tests"))))
         (encoded (hackmode-starlang:encode-tool-run document)))
    (assert-equal "run-1"
                  (cdr (assoc "runId" encoded :test #'string=))
                  "encoded runId")
    (assert-equal "subfinder"
                  (cdr (assoc "tool" encoded :test #'string=))
                  "encoded tool")
    (assert-equal "recon"
                  (cdr (assoc "kind" encoded :test #'string=))
                  "encoded kind")
    (assert-equal 0
                  (cdr (assoc "exitCode" encoded :test #'string=))
                  "encoded exitCode")
    (assert-equal "example.com"
                  (cdr (assoc "target" encoded :test #'string=))
                  "encoded target")))

(defun run-vuln-finding-document-test ()
  (let* ((evidence
           "{\"template-id\":\"http/misconfig/generic\",\"info\":{\"severity\":\"high\"},\"host\":\"example.com\"}")
         (document
           (hackmode-starlang:make-vuln-finding-document
            "run-2" "nuclei" "example.com"
            "http/misconfig/generic" "high" evidence
            :host "example.com"
            :raw '((:origin . "hackmode-starlang-tests"))))
         (encoded (hackmode-starlang:encode-vuln-finding document)))
    (assert-equal "http/misconfig/generic"
                  (cdr (assoc "templateId" encoded :test #'string=))
                  "encoded templateId")
    (assert-equal "high"
                  (cdr (assoc "severity" encoded :test #'string=))
                  "encoded severity")
    (assert-equal evidence
                  (cdr (assoc "evidence" encoded :test #'string=))
                  "exact evidence preserved")))

(defun run-nuclei-parser-test ()
  (let* ((line
           "{\"template-id\":\"cves/2021/CVE-2021-44228\",\"info\":{\"severity\":\"critical\"},\"host\":\"example.com\",\"matched-at\":\"https://example.com/\"}")
         (findings
           (hackmode-starlang:parse-nuclei-output
            (format nil "~a~%~a~%" line ""))))
    (assert (= 1 (length findings)))
    (assert-equal "cves/2021/CVE-2021-44228"
                  (getf (first findings) :template-id)
                  "template id")
    (assert-equal "critical"
                  (getf (first findings) :severity)
                  "severity")
    (assert-equal line
                  (getf (first findings) :line)
                  "exact source line")))

(defun run-nuclei-provider-test ()
  (let* ((root (fresh-test-path))
         (db (tek9:new-database "operation" :path root))
         (hackmode:*asset-event-hook*
           (make-instance 'nhooks:hook-any :handlers nil))
         (sample
           "{\"template-id\":\"http/misconfig/generic\",\"info\":{\"severity\":\"high\"},\"host\":\"scan.example.com\"}"))
    (unwind-protect
         (progn
           (tek9:open-database db)
           (hackmode:clear-capability-providers)
           (hackmode-starlang:register-nuclei-provider
            :runner
            (lambda (target)
              (declare (ignore target))
              sample))
           (let* ((target
                    (make-instance 'hackmode:domain
                                   :record "example.com"
                                   :record-type "A"))
                  (scan
                    (hackmode:run-capability
                     :vuln-scan target
                     :provider :nuclei
                     :database db))
                  (asset
                    (first (hackmode:provider-job-result-assets scan))))
             (assert (eq :succeeded
                         (hackmode:provider-job-result-state scan)))
             (assert (= 1
                        (hackmode:provider-job-result-created-count scan)))
             (assert (typep asset 'hackmode:finding))
             (assert-equal "nuclei-finding"
                          (hackmode:finding-finding-type asset)
                          "nuclei finding type")
             (assert-equal sample
                          (hackmode:finding-data asset)
                          "lossless nuclei evidence")))
      (hackmode:clear-capability-providers)
      (when (tek9:db-is-open-p db)
        (tek9:close-database db))
      (remove-test-path root))))

(defun run-registration-delegation-test ()
  (hackmode:clear-capability-providers)
  (let ((registered (hackmode-starlang:register-pentest-providers)))
    (assert (hackmode:find-capability-provider :vuln-scan :nuclei))
    (when (find-package :hackmode-provider-recon)
      (assert (member (list :subdomain-enumerate "subfinder")
                      registered :test #'equal))
      (assert (hackmode:find-capability-provider
               :subdomain-enumerate :subfinder))))
  (hackmode:clear-capability-providers))

(defun run-tests ()
  (run-spec-library-test)
  (run-tool-run-document-test)
  (run-vuln-finding-document-test)
  (run-nuclei-parser-test)
  (run-nuclei-provider-test)
  (run-registration-delegation-test)
  (format t "Hackmode Star-Lang pentest tests passed.~%")
  t)
