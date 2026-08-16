(in-package :hackmode)

(defun provider-job-actor-handler ()
  "Return a one-job worker receive function that performs backend work only."
  (lambda (message)
    (destructuring-bind (command &key capability input provider supervisor reply-to)
        message
      (case command
        (:execute
         (let ((invocation (invoke-provider capability input :provider provider)))
           (sento.actor:tell
            supervisor
            (list :complete
                  :invocation invocation
                  :reply-to reply-to))
           (sento.actor:tell sento.actor:*self* :stop)
           invocation))
        (otherwise
         (error "Unknown Hackmode provider job actor command: ~s" command))))))

(defun provider-supervisor-handler (database dispatcher)
  "Return a supervisor that fans out backend work and serializes persistence."
  (lambda (message)
    (destructuring-bind (command &key capability input provider invocation reply-to)
        message
      (case command
        (:run
         (let ((worker
                 (sento.actor-context:actor-of
                  sento.actor:*self*
                  :dispatcher dispatcher
                  :receive (provider-job-actor-handler))))
           (sento.actor:tell
            worker
            (list :execute
                  :capability capability
                  :input input
                  :provider provider
                  :supervisor sento.actor:*self*
                  :reply-to sento.actor:*sender*))
           worker))
        (:complete
         (let ((result (finalize-provider-invocation invocation database)))
           (when reply-to
             (sento.actor:tell reply-to result))
           result))
        (otherwise
         (error "Unknown Hackmode provider supervisor command: ~s" command))))))

(defun start-provider-supervisor (&key (database *db*) system dispatcher)
  "Start the provider supervisor actor and return it.

The supervisor only dispatches backend work and serializes canonical operation
store writes. Each capability invocation runs in a short-lived child actor, so
blocking providers can execute concurrently without concurrently mutating Tek9."
  (unless (and database (tek9:db-is-open-p database))
    (error "START-PROVIDER-SUPERVISOR requires an open operation database."))
  (let* ((owned-system-p (null system))
         (context (or system (ensure-hackmode-actor-system)))
         (dispatcher-id (or dispatcher (if owned-system-p :providers :shared))))
    (setf *provider-supervisor*
          (sento.actor-context:actor-of
           context
           :name "hackmode-provider-supervisor"
           :dispatcher dispatcher-id
           :receive (provider-supervisor-handler database dispatcher-id)))))

(defun dispatch-capability (capability input
                            &key provider
                              (actor *provider-supervisor*)
                              time-out)
  "Asynchronously dispatch CAPABILITY and return Sento's Future immediately."
  (unless actor
    (error "No Hackmode provider supervisor is running."))
  (let ((message (list :run
                       :capability capability
                       :input input
                       :provider provider)))
    (if time-out
        (sento.actor:ask actor message :time-out time-out)
        (sento.actor:ask actor message))))
