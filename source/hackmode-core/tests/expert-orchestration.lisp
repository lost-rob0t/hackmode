(in-package :hackmode-tests)

(defun run-expert-orchestration-tests ()
  (let* ((passive (hackmode:make-expert-engine))
         (active (hackmode:make-expert-engine :mode :active))
         (payload (hackmode:make-expert-dispatch-payload
                   :capability "dns-resolve"
                   :provider "fixture"
                   :input "example.com"))
         (action (hackmode:make-expert-active-action
                  :id "dispatch-1"
                  :kind :dispatch
                  :operation "op-1"
                  :run-id "run-1"
                  :expert-id "recon"
                  :expert-version "1"
                  :evidence-ids '("evidence-1")
                  :payload payload))
         (calls 0)
         (seen nil)
         (dispatcher
           (lambda (capability input &key provider actor time-out)
             (declare (ignore actor time-out))
             (incf calls)
             (setf seen (list capability input provider))
             :future-token)))
    (let ((dispatch
            (hackmode:dispatch-expert-action
             active action
             :operation "op-1"
             :run-id "run-1"
             :dispatcher dispatcher)))
      (assert-equal 1 calls "active dispatch calls canonical dispatcher once")
      (assert-equal '("dns-resolve" "example.com" "fixture") seen
                    "active dispatch preserves typed provider request")
      (assert-equal action (hackmode:expert-dispatch-request-action dispatch)
                    "dispatch result retains source action")
      (assert-equal :future-token (hackmode:expert-dispatch-request-result dispatch)
                    "dispatch result retains canonical dispatcher result"))
    (handler-case
        (progn
          (hackmode:dispatch-expert-action passive action
                                           :operation "op-1" :run-id "run-1"
                                           :dispatcher dispatcher)
          (error "passive Hackpert unexpectedly dispatched a provider"))
      (hackmode:expert-effect-denied () t))
    (assert-equal 1 calls "passive rejection happens before dispatch")
    (handler-case
        (progn
          (hackmode:dispatch-expert-action active action
                                           :operation "other-op" :run-id "run-1"
                                           :dispatcher dispatcher)
          (error "cross-operation action unexpectedly dispatched"))
      (hackmode:invalid-expert-action () t))
    (assert-equal 1 calls "scope mismatch happens before dispatch")
    (let ((mutation
            (hackmode:make-expert-active-action
             :id "mutation-1" :kind :discover :operation "op-1" :run-id "run-1"
             :expert-id "recon" :expert-version "1"
             :payload (hackmode:make-expert-discover-payload :asset "asset-1"))))
      (handler-case
          (progn
            (hackmode:dispatch-expert-action active mutation
                                             :operation "op-1" :run-id "run-1"
                                             :dispatcher dispatcher)
            (error "non-dispatch active action unexpectedly entered provider path"))
        (hackmode:invalid-expert-action () t)))
    (assert-equal 1 calls "provider orchestration accepts dispatch actions only")
    t))
