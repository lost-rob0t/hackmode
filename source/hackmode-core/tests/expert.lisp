(in-package :hackmode-tests)

(defun assert-expert-unavailable (thunk)
  (let ((raised nil))
    (handler-case
        (funcall thunk)
      (hackmode:expert-unavailable ()
        (setf raised t)))
    (assert raised () "Expected HACKMODE:EXPERT-UNAVAILABLE.")))

(defun assert-expert-effect-denied (thunk expected-effect)
  (let ((condition nil))
    (handler-case
        (funcall thunk)
      (hackmode:expert-effect-denied (raised)
        (setf condition raised)))
    (assert condition () "Expected HACKMODE:EXPERT-EFFECT-DENIED.")
    (assert-equal expected-effect
                  (hackmode:expert-effect-denied-effect condition)
                  "denied expert effect")
    condition))

(defun assert-invalid-expert-action (thunk)
  (let ((condition nil))
    (handler-case
        (funcall thunk)
      (hackmode:invalid-expert-action (raised)
        (setf condition raised)))
    (assert condition () "Expected HACKMODE:INVALID-EXPERT-ACTION.")
    condition))

(defun run-expert-engine-mode-test ()
  (let ((passive (hackmode:make-expert-engine))
        (active (hackmode:make-expert-engine :mode :active)))
    (assert-equal :passive (hackmode:expert-engine-mode passive)
                  "Hackpert defaults to passive authority")
    (assert-equal :active (hackmode:expert-engine-mode active)
                  "active Hackpert authority is explicit")
    (assert (hackmode:expert-engine-effect-authorized-p passive :reasoning))
    (assert (not (hackmode:expert-engine-effect-authorized-p
                  passive :provider-dispatch)))
    (assert (not (hackmode:expert-engine-effect-authorized-p
                  passive :canonical-mutation)))
    (assert (not (hackmode:expert-engine-effect-authorized-p
                  passive :active-control)))
    (assert (hackmode:expert-engine-effect-authorized-p
             active :provider-dispatch))
    (assert (hackmode:expert-engine-effect-authorized-p
             active :canonical-mutation))
    (assert (hackmode:expert-engine-effect-authorized-p
             active :active-control))
    (assert-expert-effect-denied
     (lambda ()
       (hackmode:require-expert-engine-effect passive :provider-dispatch))
     :provider-dispatch)
    (assert-expert-effect-denied
     (lambda ()
       (hackmode:require-expert-engine-effect passive :canonical-mutation))
     :canonical-mutation)
    (assert-equal :provider-dispatch
                  (hackmode:require-expert-engine-effect
                   active :provider-dispatch)
                  "active authority admits provider dispatch")
    (assert-equal :canonical-mutation
                  (hackmode:require-expert-engine-effect
                   active :canonical-mutation)
                  "active authority admits canonical mutation")
    (let ((raised nil))
      (handler-case
          (hackmode:make-expert-engine :mode :llm)
        (error () (setf raised t)))
      (assert raised () "Unsupported authority modes must fail closed."))))

(defun run-expert-active-action-test ()
  (let* ((passive (hackmode:make-expert-engine))
         (active (hackmode:make-expert-engine :mode :active))
         (payload
           (hackmode:make-expert-dispatch-payload
            :capability "dns-resolve"
            :provider "fixture"
            :input "example.com"))
         (action
           (hackmode:make-expert-active-action
            :id "action-1"
            :kind :dispatch
            :operation "op-a"
            :run-id "run-1"
            :expert-id "recon"
            :expert-version "1"
            :evidence-ids '("call-1")
            :payload payload)))
    (assert-equal :provider-dispatch
                  (hackmode:expert-active-action-effect-kind action)
                  "dispatch actions map to provider authority")
    (assert-equal action
                  (hackmode:validate-expert-active-action
                   active action
                   :operation "op-a"
                   :run-id "run-1")
                  "active action validates in its operation/run")
    (assert-expert-effect-denied
     (lambda ()
       (hackmode:validate-expert-active-action
        passive action
        :operation "op-a"
        :run-id "run-1"))
     :provider-dispatch)
    (assert-invalid-expert-action
     (lambda ()
       (hackmode:validate-expert-active-action
        active action
        :operation "op-b"
        :run-id "run-1")))
    (assert-invalid-expert-action
     (lambda ()
       (hackmode:make-expert-active-action
        :id "action-2"
        :kind :graph-delta
        :operation "op-a"
        :run-id "run-1"
        :expert-id "recon"
        :expert-version "1"
        :payload payload)))
    (dolist (kind '(:graph-delta :discover :operational-kb-delta :plan-transition))
      (assert-equal :canonical-mutation
                    (hackmode:expert-active-action-effect-kind
                     (hackmode:make-expert-active-action
                      :id (format nil "action-~a" kind)
                      :kind kind
                      :operation "op-a"
                      :run-id "run-1"
                      :expert-id "recon"
                      :expert-version "1"
                      :payload
                      (ecase kind
                        (:graph-delta
                         (hackmode:make-expert-graph-delta-payload
                          :nodes '("node-1")))
                        (:discover
                         (hackmode:make-expert-discover-payload :asset "asset-1"))
                        (:operational-kb-delta
                         (hackmode:make-expert-kb-delta-payload
                          :assertions '((hypothesis "h1"))))
                        (:plan-transition
                         (hackmode:make-expert-plan-transition-payload
                          :plan-id "plan-1"
                          :step-id "step-1"
                          :transition :advance)))))
                    "state-changing active actions map to canonical mutation"))
    (let ((control
            (hackmode:make-expert-active-action
             :id "action-control"
             :kind :control
             :operation "op-a"
             :run-id "run-1"
             :expert-id "recon"
             :expert-version "1"
             :payload
             (hackmode:make-expert-control-payload
              :directive :yield
              :reason "need evidence"))))
      (assert-equal :active-control
                    (hackmode:expert-active-action-effect-kind control)
                    "control actions require active-run authority")
      (assert-expert-effect-denied
       (lambda ()
         (hackmode:validate-expert-active-action
          passive control
          :operation "op-a"
          :run-id "run-1"))
       :active-control))))

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
  (run-expert-engine-mode-test)
  (run-expert-active-action-test)
  (run-expert-snapshot-test)
  (run-expert-unavailable-test)
  (run-live-expert-test)
  (format t "Hackmode expert tests passed.~%")
  t)
