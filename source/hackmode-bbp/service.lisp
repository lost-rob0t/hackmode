(in-package :hackmode-bbp)

(defstruct bbp-target
  (id "" :type string)
  (actor "" :type string)
  (value "" :type string)
  (dataset "star-intel" :type string)
  (sources nil :type list)
  options)

(defstruct bbp-scan-result
  target
  state
  job-id
  assets
  documents
  error)

(defvar *bbp-supervisor* nil
  "Current Hackmode BBP supervisor actor.")

(defun canonical-actor-name (actor)
  (substitute #\- #\_ (string-downcase (string actor))))

(defun ensure-target (target)
  (check-type target bbp-target)
  (dolist (field (list (bbp-target-id target)
                       (bbp-target-actor target)
                       (bbp-target-value target)
                       (bbp-target-dataset target)))
    (unless (and (stringp field) (plusp (length field)))
      (error "BBP target identity, actor, value, and dataset must be non-empty.")))
  target)

(defun target-url (value)
  (hackmode:parse-url
   (if (or (uiop:string-prefix-p "http://" value)
           (uiop:string-prefix-p "https://" value))
       value
       (format nil "https://~a" value))))

(defun bbp-target-plan (target)
  "Return CAPABILITY, PROVIDER and typed INPUT for TARGET."
  (ensure-target target)
  (let ((actor (canonical-actor-name (bbp-target-actor target)))
        (value (bbp-target-value target)))
    (cond
      ((string= actor "subfinder")
       (values :subdomain-enumerate
               :subfinder
               (make-instance 'hackmode:domain
                              :record value
                              :record-type "A"
                              :tool "subfinder")))
      ((string= actor "dns-resolver")
       (values :dns-resolve
               :massdns
               (make-instance 'hackmode:domain
                              :record value
                              :record-type "A"
                              :tool "massdns")))
      ((string= actor "httpx")
       (values :http-probe :httpx (target-url value)))
      ((string= actor "katana")
       (values :web-crawl :katana (target-url value)))
      ((string= actor "nmap")
       (values :service-enumerate
               :nmap
               (make-instance 'hackmode:host
                              :hostname value
                              :ip value
                              :tool "nmap")))
      (t
       (error "Unsupported BBP actor ~s." (bbp-target-actor target))))))

(defun result-documents (target result)
  (loop for asset in (hackmode:provider-job-result-assets result)
        for json = (hackmode:asset->starintel-json
                    asset :dataset (bbp-target-dataset target))
        when json collect json))

(defun provider-result->scan-result (target result)
  (make-bbp-scan-result
   :target target
   :state (hackmode:provider-job-result-state result)
   :job-id (hackmode:provider-job-result-id result)
   :assets (hackmode:provider-job-result-assets result)
   :documents (result-documents target result)
   :error (hackmode:provider-job-result-error result)))

(defun bbp-job-handler (database)
  (lambda (message)
    (destructuring-bind
        (command &key target capability provider input supervisor reply-to)
        message
      (case command
        (:execute
         (let ((result
                 (hackmode:run-capability
                  capability input
                  :provider provider
                  :database database)))
           (sento.actor:tell
            supervisor
            (list :complete
                  :target target
                  :result result
                  :reply-to reply-to))
           (sento.actor:tell sento.actor:*self* :stop)
           result))
        (otherwise
         (error "Unknown BBP job command: ~s" command))))))

(defun bbp-supervisor-handler (database dispatcher)
  (lambda (message)
    (destructuring-bind (command &key target result reply-to) message
      (case command
        (:scan
         (multiple-value-bind (capability provider input)
             (bbp-target-plan target)
           (let ((child
                   (sento.actor-context:actor-of
                    sento.actor:*self*
                    :dispatcher dispatcher
                    :receive (bbp-job-handler database))))
             (sento.actor:tell
              child
              (list :execute
                    :target target
                    :capability capability
                    :provider provider
                    :input input
                    :supervisor sento.actor:*self*
                    :reply-to sento.actor:*sender*))
             child)))
        (:complete
         (let ((scan-result (provider-result->scan-result target result)))
           (when reply-to
             (sento.actor:tell reply-to scan-result))
           scan-result))
        (otherwise
         (error "Unknown BBP supervisor command: ~s" command))))))

(defun start-bbp-supervisor (&key (database hackmode:*db*) system dispatcher)
  "Start BBP execution on Hackmode's shared Sento actor system."
  (unless (and database (tek9:db-is-open-p database))
    (error "START-BBP-SUPERVISOR requires an open operation database."))
  (hackmode-provider-bbp:register-bbp-providers)
  (let* ((owned-system-p (null system))
         (context (or system (hackmode:ensure-hackmode-actor-system)))
         (dispatcher-id (or dispatcher (if owned-system-p :bbp :shared))))
    (setf *bbp-supervisor*
          (sento.actor-context:actor-of
           context
           :name "hackmode-bbp-supervisor"
           :dispatcher dispatcher-id
           :receive (bbp-supervisor-handler database dispatcher-id)))))

(defun stop-bbp-supervisor ()
  "Stop only the BBP supervisor; the shared Hackmode actor system remains owned by Hackmode."
  (when *bbp-supervisor*
    (sento.actor:tell *bbp-supervisor* :stop)
    (setf *bbp-supervisor* nil))
  t)

(defun dispatch-bbp-target (target &key (actor *bbp-supervisor*) time-out)
  "Dispatch TARGET asynchronously and return Sento's future."
  (unless actor
    (error "No Hackmode BBP supervisor is running."))
  (let ((message (list :scan :target (ensure-target target))))
    (if time-out
        (sento.actor:ask actor message :time-out time-out)
        (sento.actor:ask actor message))))
