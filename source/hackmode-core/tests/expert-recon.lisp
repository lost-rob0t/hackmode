(in-package :hackmode-tests)

(defun run-expert-recon-tests ()
  (let ((dispatch-count 0)
        (operation
          (make-instance 'hackmode:operation
                         :name "recon-op"
                         :dir "/tmp/recon-op/"))
        (asset
          (make-instance 'hackmode:domain
                         :id "recon-domain"
                         :record "example.com"
                         :record-type "A"
                         :operation "recon-op")))
    (hackmode:normalize-asset asset)
    (hackmode:clear-capability-providers)
    (unwind-protect
         (progn
           (flet ((must-not-run (input)
                    (declare (ignore input))
                    (incf dispatch-count)
                    (error "Recon action selection must not execute providers.")))
             (hackmode:register-capability-provider
              :subdomain-enumerate :slow #'must-not-run
              :input-type 'hackmode:domain
              :output-types '(hackmode:domain)
              :priority 50)
             (hackmode:register-capability-provider
              :subdomain-enumerate :fast #'must-not-run
              :input-type 'hackmode:domain
              :output-types '(hackmode:domain)
              :priority 10)
             (hackmode:register-capability-provider
              :inspect :generic #'must-not-run
              :input-type t
              :priority 1))
           (let* ((action
                    (hackmode:expert-recon-next-action
                     asset
                     :operation operation
                     :run-id "run-1"
                     :assets (list asset)
                     :providers (hackmode:list-capability-providers)))
                  (payload (hackmode:expert-active-action-payload action)))
             (assert-equal :dispatch
                           (hackmode:expert-active-action-kind action)
                           "recon expert emits typed dispatch action")
             (assert-equal "recon-op"
                           (hackmode:expert-active-action-operation action)
                           "recon action preserves operation scope")
             (assert-equal "run-1"
                           (hackmode:expert-active-action-run-id action)
                           "recon action preserves run scope")
             (assert-equal "recon"
                           (hackmode:expert-active-action-expert-id action)
                           "recon action records expert identity")
             (assert-equal "subdomain-enumerate"
                           (hackmode:expert-dispatch-payload-capability payload)
                           "domain recon selects recon capability")
             (assert-equal "fast"
                           (hackmode:expert-dispatch-payload-provider payload)
                           "recon expert chooses deterministic highest-priority provider")
             (assert (eq asset (hackmode:expert-dispatch-payload-input payload)) ()
                     "typed input object must cross the action boundary unchanged")
             (assert-equal 0 dispatch-count
                           "action selection performs zero provider effects")))
      (hackmode:clear-capability-providers)))
  (format t "Hackmode recon expert tests passed.~%")
  t)
