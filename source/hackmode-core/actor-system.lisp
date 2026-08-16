(in-package :hackmode)

(defvar *hackmode-actor-system* nil
  "Hackmode-owned Sento actor system for local asynchronous workers.")

(defvar *outbox-actor* nil
  "Current Hackmode outbox actor.")

(defvar *provider-supervisor* nil
  "Current Hackmode provider supervisor actor.")

(defun ensure-hackmode-actor-system ()
  "Return the shared Hackmode actor system for local asynchronous workers."
  (or *hackmode-actor-system*
      (setf *hackmode-actor-system*
            (sento.actor-system:make-actor-system
             '(:dispatchers
               (:outbox (:workers 1 :strategy :random)
                :providers (:workers 4 :strategy :random))
               :timeout-timer
               (:resolution 100 :max-size 100))))))

(defun stop-hackmode-actor-system ()
  "Shutdown the Hackmode-owned actor system, if any."
  (when *hackmode-actor-system*
    (sento.actor-context:shutdown *hackmode-actor-system*)
    (setf *hackmode-actor-system* nil
          *outbox-actor* nil
          *provider-supervisor* nil))
  t)
