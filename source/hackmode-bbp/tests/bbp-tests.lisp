(defpackage :hackmode-bbp-tests
  (:use :cl))

(in-package :hackmode-bbp-tests)

(defun assert-equal (expected actual label)
  (assert (equal expected actual) ()
          "Expected ~a to be ~s, got ~s" label expected actual))

(defun fresh-test-path ()
  (merge-pathnames
   (format nil "hackmode-bbp-~a/" (tek9:make-key-id))
   (uiop:temporary-directory)))

(defun run-target-plan-test ()
  (let ((target
          (hackmode-bbp:make-bbp-target
           :id "target-1"
           :actor "subfinder"
           :value "Example.COM"
           :dataset "dataset-1"
           :sources '("seed"))))
    (multiple-value-bind (capability provider input)
        (hackmode-bbp:bbp-target-plan target)
      (assert (eq :subdomain-enumerate capability))
      (assert (eq :subfinder provider))
      (assert (typep input 'hackmode:domain))
      (hackmode:normalize-asset input)
      (assert-equal "example.com" (hackmode:domain-name input) "domain input"))))

(defun run-provider-parser-test ()
  (let ((http-assets
          (hackmode-provider-bbp:parse-httpx-output
           "{\"url\":\"https://Example.COM/a\"}\nnot-json\n"))
        (katana-assets
          (hackmode-provider-bbp:parse-katana-output
           "{\"endpoint\":\"https://example.com/b\"}\n")))
    (assert (= 1 (length http-assets)))
    (assert (= 1 (length katana-assets)))
    (assert-equal "example.com"
                  (hackmode:url-host (first http-assets))
                  "httpx host")
    (assert-equal "/b"
                  (hackmode:url-path (first katana-assets))
                  "katana path")))

(defun run-actor-dispatch-test ()
  (let* ((root (fresh-test-path))
         (db (tek9:new-database "bbp" :path root))
         (source (jsown:empty-object))
         (target
           (progn
             (setf (jsown:val source "kind") "manual"
                   (jsown:val source "name") "operator")
             (hackmode-bbp:make-bbp-target
              :id "target-2"
              :actor "subfinder"
              :value "example.com"
              :dataset "dataset-2"
              :sources (list source)))))
    (unwind-protect
         (progn
           (tek9:open-database db)
           (hackmode:clear-capability-providers)
           ;; START-BBP-SUPERVISOR registers production providers. Replace the
           ;; selected provider afterward so this test has no network/tool dependency.
           (hackmode-bbp:start-bbp-supervisor :database db)
           (hackmode:register-capability-provider
            :subdomain-enumerate :subfinder
            (lambda (domain)
              (declare (ignore domain))
              (list
               (make-instance 'hackmode:domain
                              :record "a.example.com"
                              :record-type "A"
                              :tool "subfinder")))
            :input-type 'hackmode:domain
            :output-types '(hackmode:domain)
            :priority 1)
           (let ((future (hackmode-bbp:dispatch-bbp-target target)))
             (multiple-value-bind (result ignored)
                 (sento.future:fawait future :timeout 2.0 :sleep-time 0.01)
               (declare (ignore ignored))
               (assert result () "BBP future did not resolve.")
               (assert (eq :succeeded
                           (hackmode-bbp:bbp-scan-result-state result)))
               ;; Legacy BBPD emits the Subfinder root plus each discovered child.
               (assert (= 2
                          (length
                           (hackmode-bbp:bbp-scan-result-documents result))))
               (assert (= 1
                          (length
                           (hackmode-bbp:bbp-scan-result-relations result))))
               (let* ((child
                        (second
                         (hackmode-bbp:bbp-scan-result-documents result)))
                      (sources (jsown:val child "sources")))
                 (assert (= 2 (length sources)))
                 (assert-equal "manual"
                               (jsown:val (first sources) "kind")
                               "inherited source kind")
                 (assert-equal "tool"
                               (jsown:val (second sources) "kind")
                               "derived tool source kind")
                 (assert-equal "subfinder"
                               (jsown:val (second sources) "name")
                               "derived tool source name")))))
      (ignore-errors (hackmode-bbp:stop-bbp-supervisor))
      (ignore-errors (hackmode:stop-hackmode-actor-system))
      (hackmode:clear-capability-providers)
      (when (tek9:db-is-open-p db)
        (tek9:close-database db))
      (ignore-errors
        (uiop:delete-directory-tree root
                                    :validate t
                                    :if-does-not-exist :ignore)))))

(defun run-tests ()
  (run-target-plan-test)
  (run-provider-parser-test)
  (run-actor-dispatch-test)
  (format t "Hackmode BBP tests passed.~%")
  t)
