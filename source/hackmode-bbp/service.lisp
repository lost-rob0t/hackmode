(in-package :hackmode-bbp)

(defstruct bbp-target
  (id "" :type string)
  (actor "" :type string)
  (value "" :type string)
  (dataset "star-intel" :type string)
  (sources nil :type list)
  options
  extensions)

(defstruct bbp-scan-result
  target
  state
  job-id
  assets
  documents
  relations
  error)

(defvar *bbp-supervisor* nil
  "Current Hackmode BBP supervisor actor.")

(defun bbp-target-from-starintel-json (payload)
  "Decode one canonical StarIntel v0.9 target into the BBP execution contract."
  (let* ((object (if (stringp payload) (jsown:parse payload) payload))
         (document (starintel:decode object 'starintel:target)))
    (make-bbp-target
     :id (starintel:doc-id document)
     :actor (starintel:target-actor document)
     :value (starintel:target-target document)
     :dataset (starintel:doc-dataset document)
     :sources (copy-list (starintel:doc-sources document))
     :options (copy-list (starintel:target-options document))
     :extensions (starintel:doc-extensions document))))

(defun make-bbp-event (actor-name event-type details source-id)
  "Create the legacy BBPD actor-event wire object."
  (let ((event (jsown:empty-object)))
    (setf (jsown:val event "_id") (starintel:make-ulid)
          (jsown:val event "timestamp") (hackmode:unix-now)
          (jsown:val event "actorName") actor-name
          (jsown:val event "eventType") event-type
          (jsown:val event "details") details
          (jsown:val event "sourceId") source-id)
    event))

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
                              :ip ""
                              :tool "nmap")))
      (t
       (error "Unsupported BBP actor ~s." (bbp-target-actor target))))))

(defun tool-source (target)
  (let ((source (jsown:empty-object)))
    (setf (jsown:val source "kind") "tool"
          (jsown:val source "name")
          (canonical-actor-name (bbp-target-actor target)))
    source))

(defun derived-sources (target)
  "Preserve inbound sources and append the BBP tool source."
  (append (copy-list (bbp-target-sources target))
          (list (tool-source target))))

(defun project-asset-document (target asset)
  (let ((document
          (hackmode:asset->starintel-document
           asset :dataset (bbp-target-dataset target))))
    (when document
      (setf (starintel:doc-sources document) (derived-sources target)
            (starintel:doc-extensions document)
            (or (bbp-target-extensions target) (jsown:empty-object)))
      document)))

(defun subfinder-root-document (target)
  (when (string= "subfinder"
                 (canonical-actor-name (bbp-target-actor target)))
    (project-asset-document
     target
     (make-instance 'hackmode:domain
                    :record (bbp-target-value target)
                    :record-type "A"
                    :tool "subfinder"))))

(defun result-document-objects (target result)
  (let ((documents
          (remove nil
                  (mapcar
                   (lambda (asset)
                     (project-asset-document target asset))
                   (hackmode:provider-job-result-assets result)))))
    (let ((root (subfinder-root-document target)))
      (if (and root
               (notany
                (lambda (document)
                  (string= (starintel:doc-id document)
                           (starintel:doc-id root)))
                documents))
          (cons root documents)
          documents))))

(defun relation-document-id (dataset source predicate target)
  "Return the legacy BBPD deterministic relation identity."
  (let* ((fields (list dataset source predicate target))
         (encoded
           (format nil "~{~a~^|~}"
                   (mapcar
                    (lambda (field)
                      (format nil "~d:~a"
                              (length (babel:string-to-octets
                                       field :encoding :utf-8))
                              field))
                    fields)))
         (digest
           (ironclad:digest-sequence
            :sha256
            (babel:string-to-octets encoded :encoding :utf-8))))
    (format nil "relation:~a"
            (string-downcase
             (ironclad:byte-array-to-hex-string digest)))))

(defun relation-spec (target)
  (let ((actor (canonical-actor-name (bbp-target-actor target))))
    (cond
      ((string= actor "subfinder")
       (values "related-to" "subfinder discovery"))
      ((string= actor "httpx")
       (values "related-to" "httpx"))
      ((string= actor "katana")
       (values "links-to" "crawl"))
      ((string= actor "nmap")
       (values "related-to" "host-discovery"))
      (t
       (values nil nil)))))

(defun relation-source-id (target documents)
  (if (string= "subfinder"
               (canonical-actor-name (bbp-target-actor target)))
      (let ((root (first documents)))
        (and root (starintel:doc-id root)))
      (bbp-target-id target)))

(defun result-relation-objects (target documents)
  (multiple-value-bind (predicate note) (relation-spec target)
    (if (null predicate)
        nil
        (let ((source-id (relation-source-id target documents))
              (root-id
                (and (string= "subfinder"
                              (canonical-actor-name
                               (bbp-target-actor target)))
                     (first documents)
                     (starintel:doc-id (first documents)))))
          (loop for document in documents
                for target-id = (starintel:doc-id document)
                unless (or (null source-id)
                           (and root-id (string= target-id root-id)))
                  collect
                    (let ((relation
                            (starintel:new-relation
                             (bbp-target-dataset target)
                             source-id
                             target-id
                             :predicate predicate
                             :note note)))
                      (setf (starintel:doc-id relation)
                            (relation-document-id
                             (bbp-target-dataset target)
                             source-id predicate target-id)
                            (starintel:doc-sources relation)
                            (derived-sources target)
                            (starintel:doc-extensions relation)
                            (or (bbp-target-extensions target)
                                (jsown:empty-object)))
                      relation))))))

(defun provider-result->scan-result (target result)
  (let* ((document-objects (result-document-objects target result))
         (relation-objects
           (result-relation-objects target document-objects)))
    (make-bbp-scan-result
     :target target
     :state (hackmode:provider-job-result-state result)
     :job-id (hackmode:provider-job-result-id result)
     :assets (hackmode:provider-job-result-assets result)
     :documents (mapcar #'starintel:encode document-objects)
     :relations (mapcar #'starintel:encode relation-objects)
     :error (hackmode:provider-job-result-error result))))

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
