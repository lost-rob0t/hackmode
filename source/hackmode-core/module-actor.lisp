(in-package :hackmode)

(defun start-module-catalog-actor (&key (registry hackmode-modules:*module-registry*)
                                    system dispatcher name)
  "Start a local catalog actor on Hackmode's shared Sento runtime.
Synchronous asks return a result; asynchronous asks and tells with a sender
receive that same protocol through an explicit reply. No module is executed."
  ;; Validate/build the receiver before allocating any runtime or threads.
  (let ((receiver (hackmode-modules:make-module-catalog-receiver :registry registry)))
    (unless (or (null name) (and (stringp name) (plusp (length name))))
      (error 'hackmode-modules:module-validation-error
             :field :name :reason "Expected a nonempty actor name."))
    (let* ((owned-system-p (null system))
           (context (or system (ensure-hackmode-actor-system)))
           (dispatcher-id (or dispatcher (if owned-system-p :providers :shared))))
      (sento.actor-context:actor-of
       context :name (when name (copy-seq name)) :dispatcher dispatcher-id
       :receive (lambda (request)
                  (let ((result (funcall receiver request)))
                    (when sento.actor:*sender*
                      (sento.actor:tell sento.actor:*sender* result))
                    result))))))
