(in-package :hackmode)

(defparameter *starintel-target-extension-key* "hackmode.target.v1"
  "Extension key used by generic Hackmode StarIntel targets.")

(defvar *target-receiver-actors* (make-hash-table :test #'equal)
  "Hackmode target receiver actors keyed by StarIntel actor name.")

(defstruct target-receiver-definition
  actor-name
  capability
  provider
  input-type)

(defstruct target-dispatch-request
  actor-name
  target-id
  dataset
  execution-id
  capability
  provider
  input)

(defun target-json-value (object key &optional default)
  "Read KEY from a JSOWN OBJECT, returning DEFAULT when absent."
  (if object
      (let ((value (jsown:val-safe object key)))
        (if (null value) default value))
      default))

(defun target-data-object (document)
  "Return the canonical target data object from DOCUMENT."
  (or (target-json-value document "data")
      document))

(defun target-data-value (document key &optional default)
  "Read KEY from canonical target data, with top-level compatibility fallback."
  (let* ((data (target-data-object document))
         (value (target-json-value data key :missing)))
    (if (eq value :missing)
        (target-json-value document key default)
        value)))

(defun target-extension-object (document)
  (let* ((extensions (target-json-value document "extensions"))
         (extension (and extensions
                         (target-json-value extensions
                                            *starintel-target-extension-key*))))
    extension))

(defun required-target-string (document key)
  (let ((value (target-data-value document key)))
    (unless (and (stringp value) (plusp (length value)))
      (error "StarIntel target field ~a must be a non-empty string." key))
    value))

(defun optional-target-string (object key)
  (let ((value (target-json-value object key)))
    (and (stringp value) (plusp (length value)) value)))

(defun target-execution-id (document)
  "Return StarIntel execution identity injected by the target dispatcher, if any."
  (let ((extensions (target-json-value document "extensions")))
    (or (optional-target-string extensions "target_execution_id")
        (optional-target-string (target-extension-object document) "execution_id"))))

(defun target-actor-component (value)
  (string-downcase
   (cl-ppcre:regex-replace-all
    "[^A-Za-z0-9._:-]+"
    (string value)
    "-")))

(defun provider-target-actor-name (capability provider)
  "Return the stable StarIntel actor name for a Hackmode provider."
  (format nil "hackmode.~a.~a"
          (target-actor-component capability)
          (target-actor-component provider)))

(defun provider-target-definition (definition)
  "Build a target receiver definition from a registered capability provider."
  (make-target-receiver-definition
   :actor-name
   (provider-target-actor-name
    (capability-provider-capability definition)
    (capability-provider-name definition))
   :capability (capability-provider-capability definition)
   :provider (capability-provider-name definition)
   :input-type (capability-provider-input-type definition)))

(defun generic-target-definition ()
  "Return the generic Hackmode target receiver definition.

Generic targets carry capability/provider selection in the
`hackmode.target.v1` extension."
  (make-target-receiver-definition
   :actor-name "hackmode"
   :capability nil
   :provider nil
   :input-type nil))

(defun target-provider-selection (document definition)
  "Resolve capability/provider for DOCUMENT and receiver DEFINITION."
  (let* ((extension (target-extension-object document))
         (capability
           (or (target-receiver-definition-capability definition)
               (optional-target-string extension "capability")))
         (provider
           (or (target-receiver-definition-provider definition)
               (optional-target-string extension "provider"))))
    (unless capability
      (error "Generic Hackmode targets require extensions.~a.capability."
             *starintel-target-extension-key*))
    (values capability provider)))

(defun target-context-tags (document)
  "Return context tags retained on typed target inputs."
  (let ((dataset (target-json-value document "dataset"))
        (target-id (target-json-value document "_id"))
        (execution-id (target-execution-id document))
        tags)
    (when (and (stringp dataset) (plusp (length dataset)))
      (push (format nil "dataset:~a" dataset) tags))
    (when (and (stringp target-id) (plusp (length target-id)))
      (push (format nil "target:~a" target-id) tags))
    (when execution-id
      (push (format nil "execution:~a" execution-id) tags))
    (nreverse tags)))

(defun target-operation-name (document)
  "Return Hackmode operation context requested by DOCUMENT, if supplied."
  (let* ((extension (target-extension-object document))
         (operation (optional-target-string extension "operation")))
    (or operation
        (let ((target-id (target-json-value document "_id")))
          (if (stringp target-id) target-id "starintel-target")))))

(defun parse-target-url (value document)
  "Convert an HTTP(S) target VALUE into a Hackmode URL object."
  (cl-ppcre:register-groups-bind
      (scheme host port path query)
      ("^(https?)://([^/:?#]+)(?::([0-9]+))?([^?#]*)?(?:\\?([^#]*))?" value)
    (unless scheme
      (error "URL target must use http:// or https://: ~s" value))
    (let ((resolved-port
            (if port
                (parse-integer port)
                (if (string-equal scheme "https") 443 80))))
      (make-instance
       'url
       :scheme (string-downcase scheme)
       :host host
       :port resolved-port
       :path (or path "")
       :query (or query "")
       :operation (target-operation-name document)
       :tags (target-context-tags document)
       :tool "starintel-target"))))

(defun target-value->typed-input (value target-type input-type document)
  "Convert StarIntel target VALUE into the provider's Hackmode input type."
  (let* ((type-name
           (and input-type
                (string-downcase
                 (if (symbolp input-type)
                     (symbol-name input-type)
                     (string input-type)))))
         (input
           (cond
             ((or (string= (or type-name "") "domain")
                  (and (null input-type) (string-equal target-type "domain")))
              (make-instance 'domain
                             :record value
                             :record-type "A"
                             :operation (target-operation-name document)
                             :tags (target-context-tags document)
                             :tool "starintel-target"))
             ((or (string= (or type-name "") "host")
                  (and (null input-type)
                       (member (string-downcase target-type)
                               '("host" "hostname" "ip" "ipv4" "ipv6")
                               :test #'string=)))
              (let ((address-p
                      (member (string-downcase target-type)
                              '("ip" "ipv4" "ipv6")
                              :test #'string=)))
                (make-instance 'host
                               :hostname (if address-p "" value)
                               :ip (if address-p value "")
                               :operation (target-operation-name document)
                               :tags (target-context-tags document)
                               :tool "starintel-target")))
             ((or (string= (or type-name "") "url")
                  (and (null input-type) (string-equal target-type "url")))
              (parse-target-url value document))
             (input-type
              (error "No StarIntel target converter for Hackmode input type ~s."
                     input-type))
             (t value))))
    (when (typep input 'meta)
      (normalize-asset input))
    input))

(defun starintel-target->dispatch-request (document definition)
  "Validate DOCUMENT and convert it into a Hackmode provider dispatch request."
  (unless document
    (error "StarIntel target document is required."))
  (let* ((actor-name (required-target-string document "actor"))
         (expected (target-receiver-definition-actor-name definition))
         (target-id (or (target-json-value document "_id") ""))
         (dataset (or (target-json-value document "dataset") ""))
         (target (required-target-string document "target"))
         (target-type (or (target-data-value document "target_type") "string")))
    (unless (string-equal actor-name expected)
      (error "Target actor ~s does not match Hackmode receiver ~s."
             actor-name expected))
    (multiple-value-bind (capability provider)
        (target-provider-selection document definition)
      (let* ((provider-definition
               (find-capability-provider capability provider))
             (input-type
               (or (target-receiver-definition-input-type definition)
                   (and provider-definition
                        (capability-provider-input-type provider-definition))))
             (input
               (target-value->typed-input target target-type input-type document)))
        (make-target-dispatch-request
         :actor-name expected
         :target-id target-id
         :dataset dataset
         :execution-id (target-execution-id document)
         :capability capability
         :provider provider
         :input input)))))

(defun target-receiver-handler (definition &key (dispatch-fn #'dispatch-capability))
  "Return a Sento receive function for one StarIntel target receiver."
  (lambda (document)
    (let ((request (starintel-target->dispatch-request document definition)))
      (funcall dispatch-fn
               (target-dispatch-request-capability request)
               (target-dispatch-request-input request)
               :provider (target-dispatch-request-provider request)))))

(defun start-target-receiver (definition &key system dispatcher dispatch-fn)
  "Start one Hackmode StarIntel target receiver and return its actor ref."
  (let* ((context (or system (ensure-hackmode-actor-system)))
         (dispatcher-id (or dispatcher (if system :shared :providers)))
         (actor-name (target-receiver-definition-actor-name definition))
         (actor
           (sento.actor-context:actor-of
            context
            :name actor-name
            :dispatcher dispatcher-id
            :receive
            (target-receiver-handler
             definition
             :dispatch-fn (or dispatch-fn #'dispatch-capability)))))
    (setf (gethash actor-name *target-receiver-actors*) actor)
    actor))

(defun starintel-register-local-target-actor (actor-name actor)
  "Register ACTOR with StarIntel Server when its local actor index is loaded.

Return true when registration occurred. This keeps Hackmode independently
loadable while enabling direct target delivery in an embedded StarIntel Server
image."
  (let* ((package (find-package :star.actors))
         (symbol (and package (find-symbol "REGISTER-ACTOR" package))))
    (when (and symbol (fboundp symbol))
      (funcall symbol actor-name actor)
      t)))

(defun start-starintel-target-receivers
    (&key system dispatcher dispatch-fn (register-local t) (include-generic t))
  "Start Hackmode target receivers for all registered providers.

Each provider receives a stable `hackmode.<capability>.<provider>` actor name.
When INCLUDE-GENERIC is true, also start `hackmode`, whose targets select the
capability and optional provider using the `hackmode.target.v1` extension."
  (let ((definitions
          (append
           (when include-generic (list (generic-target-definition)))
           (mapcar #'provider-target-definition
                   (list-capability-providers))))
        actors)
    (dolist (definition definitions (nreverse actors))
      (let* ((actor-name (target-receiver-definition-actor-name definition))
             (actor (or (gethash actor-name *target-receiver-actors*)
                        (start-target-receiver
                         definition
                         :system system
                         :dispatcher dispatcher
                         :dispatch-fn dispatch-fn))))
        (when register-local
          (starintel-register-local-target-actor actor-name actor))
        (push actor actors)))))

(defun stop-starintel-target-receivers ()
  "Stop all Hackmode target receivers and clear their process-local index."
  (maphash
   (lambda (actor-name actor)
     (declare (ignore actor-name))
     (ignore-errors (sento.actor:tell actor :stop)))
   *target-receiver-actors*)
  (clrhash *target-receiver-actors*)
  t)
