(in-package :hackmode)

(defun provider-supervisor-handler (database)
  "Return a Sento receive function for asynchronous capability execution."
  (lambda (message)
    (destructuring-bind (command &key capability input provider) message
      (case command
        (:run
         (let ((result (execute-provider-job capability input
                                             :provider provider
                                             :database database)))
           (when sento.actor:*sender*
             (sento.actor:tell sento.actor:*sender* result))
           result))
        (otherwise
         (error "Unknown Hackmode provider supervisor command: ~s" command))))))

(defun start-provider-supervisor (&key (database *db*) system dispatcher)
  "Start the provider supervisor actor and return it.

The supervisor isolates blocking provider work from shell/Emacs callers. When
SYSTEM is omitted, providers use Hackmode's dedicated :PROVIDERS dispatcher."
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
           :receive (provider-supervisor-handler database)))))

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
