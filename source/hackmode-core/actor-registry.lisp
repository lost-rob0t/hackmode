(in-package :hackmode)

(defparameter *starintel-actor-registry-base-url*
  *starintel-ingest-base-url*
  "StarIntel base URL used for actor/service registry registration.")

(defparameter *starintel-actor-registry-path* "/v1/registry/manifests"
  "Canonical StarIntel actor/service manifest registration path.")

(defparameter *starintel-actor-registry-authority*
  (or (uiop:getenv "HACKMODE_STARINTEL_AUTHORITY")
      (uiop:getenv "STARINTEL_AUTHORITY")
      "local")
  "STAR URI authority advertised by this Hackmode instance.")

(defparameter *starintel-actor-registry-headers-function* nil
  "Optional function returning request headers for registry registration.")

(defparameter +hackmode-tool-spec-plugin+ "org.starintel/plugin/tool-actor@0")
(defparameter +hackmode-tool-spec-version+ "0.9.1.3")
(defparameter +hackmode-semantic-version+ "0.3.0")

(defun keyword-plist-p (value)
  (and (proper-plist-p value)
       (loop for tail on value by #'cddr
             always (keywordp (car tail)))))

(defun registry-json-key (key)
  (let* ((source (string-downcase (symbol-name key)))
         (parts (uiop:split-string source :separator '(#\-))))
    (with-output-to-string (out)
      (write-string (or (first parts) "") out)
      (dolist (part (rest parts))
        (when (plusp (length part))
          (write-char (char-upcase (char part 0)) out)
          (write-string (subseq part 1) out))))))

(defun registry-json-value (value)
  (cond
    ((null value) nil)
    ((keywordp value) (string-downcase (symbol-name value)))
    ((and (listp value) (keyword-plist-p value))
     (registry-plist->json value))
    ((listp value)
     (mapcar #'registry-json-value value))
    ((symbolp value) (string-downcase (symbol-name value)))
    (t value)))

(defun registry-plist->json (plist)
  (let ((object (jsown:empty-object)))
    (loop for (key value) on plist by #'cddr
          do (setf (jsown:val object (registry-json-key key))
                   (registry-json-value value)))
    object))

(defun safe-registry-descriptor (descriptor)
  "Return DESCRIPTOR stripped of process-local execution details."
  (let ((copy (copy-tree descriptor)))
    (remf copy :executable)
    copy))

(defun semantic-registry-descriptor (descriptor)
  (let ((copy (safe-registry-descriptor descriptor)))
    (remf copy :availability)
    copy))

(defun descriptor-semantic-digest (descriptor)
  (starintel:digest-id
   "hackmode-tool-actor-semantic-v1"
   (with-standard-io-syntax
     (let ((*print-readably* t)
           (*print-pretty* nil))
       (prin1-to-string (semantic-registry-descriptor descriptor))))))

(defun actor-resource-uri (path)
  (format nil "star://~a/actor/~a"
          *starintel-actor-registry-authority*
          path))

(defun tool-resource-path (descriptor)
  (format nil "hackmode/tool/~a/~a"
          (getf descriptor :capability)
          (getf descriptor :provider)))

(defun tool-actor-registry-resource (descriptor)
  "Project one safe Hackmode descriptor to the StarIntel registry contract."
  (let ((safe (safe-registry-descriptor descriptor)))
    (list
     :resource-uri (actor-resource-uri (tool-resource-path safe))
     :resource-kind "actor"
     :name (getf safe :name)
     :semantic-version +hackmode-semantic-version+
     :semantic-digest (descriptor-semantic-digest safe)
     :source-package "lost-rob0t/hackmode"
     :accepts '("hackmode.tool.command.v1")
     :produces (copy-list (getf safe :produces))
     :capabilities (list (getf safe :capability))
     :tools (list (getf safe :provider))
     :target-shapes (copy-tree (getf safe :target-shapes))
     :arguments (copy-tree (getf safe :arguments))
     :example-targets (copy-tree (getf safe :example-targets))
     :platform-requirements (copy-list (getf safe :platforms))
     :packages (copy-tree (getf safe :packages))
     :availability (getf safe :availability)
     :spec-plugins
     (list (list :name +hackmode-tool-spec-plugin+
                 :version +hackmode-tool-spec-version+))
     :metadata (copy-tree (getf safe :metadata)))))

(defun hackmode-root-registry-resource (tool-resources)
  (let ((capabilities
          (sort
           (remove-duplicates
            (loop for resource in tool-resources
                  append (copy-list (getf resource :capabilities)))
            :test #'string=)
           #'string<)))
    (let* ((semantic
             (list :name +hackmode-root-actor-name+
                   :capabilities capabilities
                   :accepts '("hackmode.control.v1")
                   :produces '("hackmode.tool.result.v1")))
           (digest
             (starintel:digest-id
              "hackmode-root-registry-semantic-v1"
              (with-standard-io-syntax
                (prin1-to-string semantic)))))
      (list
       :resource-uri (actor-resource-uri "hackmode")
       :resource-kind "actor"
       :name +hackmode-root-actor-name+
       :semantic-version +hackmode-semantic-version+
       :semantic-digest digest
       :source-package "lost-rob0t/hackmode"
       :accepts '("hackmode.control.v1")
       :produces '("hackmode.tool.result.v1")
       :capabilities capabilities
       :tools
       (mapcar (lambda (resource) (getf resource :resource-uri))
               tool-resources)
       :availability :online
       :spec-plugins
       (list (list :name +hackmode-tool-spec-plugin+
                   :version +hackmode-tool-spec-version+))))))

(defun hackmode-actor-manifest ()
  "Return Hackmode's canonical emitted actor/service registry manifest plist."
  (sync-tool-actors)
  (let* ((tool-resources
           (mapcar #'tool-actor-registry-resource
                   (list-tool-actor-descriptors)))
         (root (hackmode-root-registry-resource tool-resources))
         (resources (cons root tool-resources))
         (semantic-digest
           (starintel:digest-id
            "hackmode-registry-manifest-v1"
            (with-standard-io-syntax
              (prin1-to-string
               (mapcar (lambda (resource)
                         (list (getf resource :resource-uri)
                               (getf resource :semantic-digest)))
                       resources))))))
    (list
     :manifest-version +hackmode-tool-spec-version+
     :manifest-digest semantic-digest
     :source-package "lost-rob0t/hackmode"
     :generated-at (unix-now)
     :spec-plugins
     (list (list :name +hackmode-tool-spec-plugin+
                 :version +hackmode-tool-spec-version+))
     :resources resources)))

(defun encode-hackmode-actor-manifest (&optional (manifest (hackmode-actor-manifest)))
  "Encode MANIFEST as registry JSON."
  (jsown:to-json (registry-plist->json manifest)))

(defun starintel-registry-url (&key
                                 (base-url *starintel-actor-registry-base-url*)
                                 (path *starintel-actor-registry-path*))
  (format nil "~a~a" (string-right-trim "/" base-url) path))

(defun registry-request-headers ()
  (append
   '(("Content-Type" . "application/json")
     ("Accept" . "application/json"))
   (when *starintel-actor-registry-headers-function*
     (funcall *starintel-actor-registry-headers-function*))))

(defun registry-event-id (manifest kind &optional details)
  (starintel:digest-id
   "hackmode-registry-event-v1"
   (getf manifest :manifest-digest)
   (string-downcase (symbol-name kind))
   (or details "")))

(defun register-hackmode-with-starintel (&key
                                           (manifest (hackmode-actor-manifest))
                                           (connect-timeout 5)
                                           (read-timeout 10))
  "Register MANIFEST with StarIntel and journal request/outcome locally.

Registration is idempotent by MANIFEST-DIGEST. Network failure never prevents
Hackmode from operating locally; the failed outcome remains visible in the
replay journal and a later startup/refresh may retry it."
  (let* ((digest (getf manifest :manifest-digest))
         (payload (encode-hackmode-actor-manifest manifest))
         (url (starintel-registry-url)))
    (append-hackmode-actor-event
     +hackmode-runtime-stream+
     :registry-registration-requested
     (list :manifest-digest digest :url url)
     :event-id (registry-event-id manifest :requested))
    (handler-case
        (multiple-value-bind (body status)
            (dex:post url
                      :content payload
                      :headers (registry-request-headers)
                      :connect-timeout connect-timeout
                      :read-timeout read-timeout)
          (if (and (integerp status) (<= 200 status 299))
              (progn
                (append-hackmode-actor-event
                 +hackmode-runtime-stream+
                 :registry-registration-accepted
                 (list :manifest-digest digest :status status)
                 :event-id
                 (registry-event-id manifest :accepted (princ-to-string status)))
                (values body status))
              (error "StarIntel registry returned HTTP ~a: ~a" status body)))
      (dex:http-request-failed (condition)
        (let* ((status (dex:response-status condition))
               (body (dex:response-body condition))
               (message (format nil "HTTP ~a: ~a" status body)))
          (append-hackmode-actor-event
           +hackmode-runtime-stream+
           :registry-registration-failed
           (list :manifest-digest digest :error message)
           :event-id (registry-event-id manifest :failed message))
          (values body status)))
      (condition (condition)
        (let ((message (princ-to-string condition)))
          (append-hackmode-actor-event
           +hackmode-runtime-stream+
           :registry-registration-failed
           (list :manifest-digest digest :error message)
           :event-id (registry-event-id manifest :failed message))
          (warn "Hackmode StarIntel registry registration failed: ~a" condition)
          (values nil nil))))))

(defun refresh-hackmode-starintel-registration ()
  "Refresh tool actors and re-submit the current registry manifest."
  (sync-tool-actors)
  (register-hackmode-with-starintel))

(nhooks:add-hook
 *startup-hook*
 (lambda ()
   (handler-case
       (register-hackmode-with-starintel)
     (condition (condition)
       (warn "Hackmode registry startup registration failed: ~a" condition)))))
