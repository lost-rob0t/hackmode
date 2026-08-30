(in-package :hackmode-tests)

(defun assert-expert-unavailable (thunk)
  (let ((raised nil))
    (handler-case
        (funcall thunk)
      (hackmode:expert-unavailable ()
        (setf raised t)))
    (assert raised () "Expected HACKMODE:EXPERT-UNAVAILABLE.")))

(defun run-expert-snapshot-test ()
  (let* ((operation (make-instance 'hackmode:operation
                                   :name "expert-op"
                                   :dir "/tmp/expert-op/"))
         (asset (make-instance 'hackmode:domain
                               :id "asset-domain-1"
                               :record "Example.COM."
                               :record-type "A"
                               :operation "expert-op"))
         (before-id (hackmode:doc-id asset)))
    (hackmode:normalize-asset asset)
    (hackmode:clear-capability-providers)
    (unwind-protect
         (progn
           (hackmode:register-capability-provider
            :dns-resolve :fixture
            (lambda (input)
              (declare (ignore input))
              (error "Expert recommendation must not execute providers."))
            :input-type 'hackmode:domain
            :output-types '(hackmode:host)
            :priority 20)
           (let ((snapshot
                   (hackmode:expert-snapshot
                    :operation operation
                    :assets (list asset)
                    :providers (hackmode:list-capability-providers)
                    :query-target "evil.example\"). halt. %")))
             (assert (search "operation(\"expert-op\")." snapshot))
             (assert (search "asset(\"asset-domain-1\",\"domain\",\"example.com|A\")."
                             snapshot))
             (assert (search "provider(\"dns-resolve\",\"fixture\",\"domain\",20)."
                             snapshot))
             (assert (search "\\\"" snapshot) ()
                     "Embedded quotes must be escaped in Prolog data facts."))
           (assert-equal before-id (hackmode:doc-id asset)
                         "expert snapshot does not mutate asset identity"))
      (hackmode:clear-capability-providers))))

(defun run-expert-unavailable-test ()
  (let ((hackmode:*expert-program* "hackmode-swipl-definitely-missing"))
    (assert (not (hackmode:expert-available-p)))
    (assert-expert-unavailable
     (lambda ()
       (hackmode:expert-classify-target
        "example.com"
        :operation nil
        :assets nil
        :providers nil)))))

(defun run-live-expert-test ()
  (unless (hackmode:expert-available-p)
    (format t "Skipping live Hackmode expert tests: swipl unavailable.~%")
    (return-from run-live-expert-test t))
  (assert-equal :domain
                (hackmode:expert-classify-target
                 "example.com" :operation nil :assets nil :providers nil)
                "domain classification")
  (assert-equal :url
                (hackmode:expert-classify-target
                 "https://example.com/a?b=1"
                 :operation nil :assets nil :providers nil)
                "URL classification")
  (assert-equal :ipv4
                (hackmode:expert-classify-target
                 "192.0.2.10" :operation nil :assets nil :providers nil)
                "IPv4 classification")
  (assert-equal :ipv6
                (hackmode:expert-classify-target
                 "::1" :operation nil :assets nil :providers nil)
                "IPv6 classification")
  (assert-equal :unknown
                (hackmode:expert-classify-target
                 "evil.example\"). halt. %"
                 :operation nil :assets nil :providers nil)
                "quoted input remains inert data")
  (let ((asset (make-instance 'hackmode:domain
                              :id "asset-domain-2"
                              :record "example.net"
                              :record-type "A")))
    (hackmode:normalize-asset asset)
    (hackmode:clear-capability-providers)
    (unwind-protect
         (progn
           (flet ((must-not-run (input)
                    (declare (ignore input))
                    (error "Expert recommendation executed a provider.")))
             (hackmode:register-capability-provider
              :dns-resolve :slow #'must-not-run
              :input-type 'hackmode:domain :priority 50)
             (hackmode:register-capability-provider
              :dns-resolve :fast #'must-not-run
              :input-type 'hackmode:domain :priority 10)
             (hackmode:register-capability-provider
              :crawl :crawler #'must-not-run
              :input-type 'hackmode:url :priority 1)
             (hackmode:register-capability-provider
              :inspect :generic #'must-not-run
              :input-type t :priority 100))
           (let* ((recommendations
                    (hackmode:expert-recommend-capabilities
                     asset
                     :operation nil
                     :assets (list asset)
                     :providers (hackmode:list-capability-providers)))
                  (rows
                    (mapcar
                     (lambda (recommendation)
                       (list (hackmode:expert-recommendation-priority recommendation)
                             (hackmode:expert-recommendation-capability recommendation)
                             (hackmode:expert-recommendation-provider recommendation)))
                     recommendations)))
             (assert-equal
              '((10 "dns-resolve" "fast")
                (50 "dns-resolve" "slow")
                (100 "inspect" "generic"))
              rows
              "deterministic compatible provider recommendations")))
      (hackmode:clear-capability-providers)))
  t)

(defun run-expert-tests ()
  (run-expert-snapshot-test)
  (run-expert-unavailable-test)
  (run-live-expert-test)
  (format t "Hackmode expert tests passed.~%")
  t)
