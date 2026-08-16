(in-package :hackmode)

(defun provider-job-actor-handler (database)
  "Return a one-job worker receive function bound to DATABASE."
  (lambda (message)
    (destructuring-bind (command &key capability input provider reply-to) message
      (case command
        (:execute
         (let ((result (execute-provider-job capability input
                                             :provider provider
                                             :database database)))
           (when reply-to
             (sento.actor:tell reply-to result))
           (sento.actor:tell sento.actor:*self* :stop)
           result))
        (otherwise
         (error "Unknown Hackmode provider job actor command: ~s" command))))))

(defun provider-supervisor-handler (database dispatcher)
  "Return a supervisor receive function that fans jobs out to child actors."
  (lambda (message)
    (destructuring-bind (command &key capability input provider) message
      (case command
        (:run
         (let ((worker
                 (sento.actor-context:actor-of
                  sento.actor:*self*
                  :dispatcher dispatcher
                  :receive (provider-job-actor-handler database))))
           (sento.actor:tell
            worker
            (list :execute
                  :capability capability
                  :input input
                  :provider provider
                  :reply-to sento.actor:*sender*))
           worker))
        (otherwise
         (error "Unknown Hackmode provider supervisor command: ~s" command))))))

(defun start-provider-supervisor (&key (database *db*) system dispatcher)
  "Start the provider supervisor actor and return it.

The supervisor itself only dispatches work. Each capability invocation runs in
a short-lived child actor on the provider dispatcher so blocking backends do not
serialize unrelated jobs or block shell/Emacs callers."
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
