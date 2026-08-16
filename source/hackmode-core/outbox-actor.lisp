(in-package :hackmode)

(defun outbox-actor-handler (database transport)
  "Return a Sento receive function bound to DATABASE and TRANSPORT."
  (lambda (message)
    (destructuring-bind (command &key now (limit 100)) message
      (case command
        (:drain
         (drain-outbox database transport
                       :now (or now (unix-now))
                       :limit limit))
        (otherwise
         (error "Unknown Hackmode outbox actor command: ~s" command))))))

(defun start-outbox-actor (&key
                            (database *db*)
                            (transport (make-starintel-http-transport))
                            system
                            dispatcher)
  "Start an asynchronous outbox actor and return it.

When SYSTEM is omitted Hackmode uses the shared actor runtime's dedicated
:OUTBOX dispatcher. Callers embedding Hackmode in another actor runtime may
supply SYSTEM and DISPATCHER explicitly."
  (unless (and database (tek9:db-is-open-p database))
    (error "START-OUTBOX-ACTOR requires an open operation database."))
  (let* ((owned-system-p (null system))
         (context (or system (ensure-hackmode-actor-system)))
         (dispatcher-id (or dispatcher (if owned-system-p :outbox :shared))))
    (setf *outbox-actor*
          (sento.actor-context:actor-of
           context
           :name "hackmode-outbox"
           :dispatcher dispatcher-id
           :receive (outbox-actor-handler database transport)))))

(defun drain-outbox-async (&key
                            (actor *outbox-actor*)
                            now
                            (limit 100))
  "Request asynchronous outbox delivery through ACTOR and return immediately."
  (unless actor
    (error "No Hackmode outbox actor is running."))
  (sento.actor:tell actor (list :drain :now now :limit limit))
  actor)
