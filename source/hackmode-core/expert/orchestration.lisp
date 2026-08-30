(in-package :hackmode)

(defstruct expert-dispatch-request
  "Result of admitting one Hackpert dispatch action into Hackmode's provider path."
  action
  result)

(defun dispatch-expert-action (engine action
                               &key operation run-id
                                 (dispatcher #'dispatch-capability)
                                 actor time-out)
  "Validate ACTION, then route a dispatch request through Hackmode's canonical provider dispatcher.

This function owns no tool executor and performs no direct persistence. It only
admits one :DISPATCH action after authority/scope validation and delegates the
actual execution path to DISPATCHER, which defaults to DISPATCH-CAPABILITY."
  (check-type dispatcher function)
  (validate-expert-active-action engine action
                                 :operation operation
                                 :run-id run-id)
  (unless (eq :dispatch (expert-active-action-kind action))
    (invalid-expert-action action
                           "provider orchestration accepts :DISPATCH actions only"))
  (let* ((payload (expert-active-action-payload action))
         (result
           (funcall dispatcher
                    (expert-dispatch-payload-capability payload)
                    (expert-dispatch-payload-input payload)
                    :provider (expert-dispatch-payload-provider payload)
                    :actor actor
                    :time-out time-out)))
    (make-expert-dispatch-request :action action :result result)))

(export '(expert-dispatch-request
          make-expert-dispatch-request
          expert-dispatch-request-action
          expert-dispatch-request-result
          dispatch-expert-action))
