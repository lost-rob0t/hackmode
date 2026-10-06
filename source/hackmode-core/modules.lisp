(in-package :hackmode-modules)

(define-condition module-validation-error (error)
  ((field :initarg :field :reader module-error-field)
   (reason :initarg :reason :reader module-error-reason))
  (:report (lambda (condition stream)
             (format stream "Invalid module ~a: ~a"
                     (module-error-field condition)
                     (module-error-reason condition)))))

(defun %invalid (field reason)
  (error 'module-validation-error :field field :reason (copy-seq reason)))

(defun %copy-data (value field)
  "Copy local scalar/cons data, preserving symbols and dotted pairs exactly.
Reject executable/opaque objects and cycles rather than changing their meaning."
  (let ((active (make-hash-table :test #'eq)))
    (labels ((walk (item)
               (cond
                 ((stringp item) (copy-seq item))
                 ((consp item)
                  (when (gethash item active) (%invalid field "Cyclic data."))
                  (setf (gethash item active) t)
                  (unwind-protect
                       (cons (walk (car item)) (walk (cdr item)))
                    (remhash item active)))
                 ((or (null item) (symbolp item) (numberp item) (characterp item))
                  item)
                 (t (%invalid field "Expected scalar or cons data; opaque objects are unsupported.")))))
      (walk value))))

(defun %proper-list (value field)
  ;; Copy first so the traversal cannot hang on a circular list.
  (let ((copy (%copy-data value field)))
    (loop for tail = copy then (cdr tail)
          while (consp tail)
          finally (unless (null tail) (%invalid field "Expected a proper list.")))
    copy))

(defun %name (value field)
  (unless (or (and value (symbolp value)) (stringp value))
    (%invalid field "Expected a nonempty name string or symbol."))
  (let ((name (string-downcase (string value))))
    (unless (and (plusp (length name))
                 (every (lambda (character)
                          (or (char<= #\a character #\z)
                              (char<= #\0 character #\9)
                              (find character "-._/@+" :test #'char=)))
                        name))
      (%invalid field "Names may contain only ASCII letters, digits, and -._/@+."))
    name))

(defun %text (value field &optional allow-empty)
  (unless (and (stringp value) (or allow-empty (plusp (length value))))
    (%invalid field "Expected a nonempty string."))
  (copy-seq value))

(defun %optional-text (value field)
  (when value (%text value field)))

(defun %names (value field)
  (mapcar (lambda (item) (%name item field)) (%proper-list value field)))

(defun %texts (value field)
  (mapcar (lambda (item) (%text item field t)) (%proper-list value field)))

(defun %metadata-strings (value field)
  (mapcar (lambda (item) (%text item field)) (%proper-list value field)))

(defun %boolean (value field)
  (unless (or (eq value t) (null value)) (%invalid field "Expected T or NIL."))
  value)

(defclass module-option ()
  ((data :initarg :data :reader %option-data)))

(defun %option-type (type)
  (let ((name (%name type :type)))
    (or (find name '(:string :integer :boolean :enum :string-list
                    :asset-reference :path :credential-reference)
              :key (lambda (item) (string-downcase (symbol-name item)))
              :test #'string=)
        (%invalid :type "Unknown module option type."))))

(defun %check-option-value (info value)
  (%copy-data value :options)
  (let ((valid
          (case (getf info :type)
            (:string (stringp value))
            (:integer (integerp value))
            (:boolean (or (eq value t) (null value)))
            (:enum (member value (getf info :choices) :test #'equal))
            (:string-list (every #'stringp (%proper-list value :options)))
            ((:asset-reference :path :credential-reference)
             (and (stringp value) (plusp (length value)))))))
    (unless valid (%invalid :options "Option value does not match its declared type.")))
  value)

(defun make-module-option (&key name (type :string) (description "")
                             (required nil required-supplied-p)
                             (required-p nil required-p-supplied-p)
                             choices (default nil default-supplied-p)
                             (default-present-p default-supplied-p))
  "Describe an option. NIL is a boolean value, distinct from an absent default.
Reference and path options describe opaque strings; they never dereference them."
  (when (and required-supplied-p required-p-supplied-p
             (not (eql required required-p)))
    (%invalid :required "Conflicting REQUIRED and REQUIRED-P values."))
  (let* ((kind (%option-type type))
         (enum-choices (%proper-list choices :choices))
         (info (list :name (%name name :name)
                     :type kind :description (%text description :description t)
                     :required (%boolean (if required-p-supplied-p required-p required)
                                         :required)
                     :choices enum-choices
                     :default-present-p (%boolean default-present-p :default-present-p)
                     :default (if default-present-p (%copy-data default :default) nil))))
    (when (and (eq kind :enum) (null enum-choices))
      (%invalid :choices "Enum options require at least one choice."))
    (when (and (not (eq kind :enum)) enum-choices)
      (%invalid :choices "Choices apply only to enum options."))
    (when default-present-p (%check-option-value info default))
    (make-instance 'module-option :data info)))

(defun module-option-info (option)
  (unless (typep option 'module-option) (%invalid :option "Expected a module option."))
  (%copy-data (%option-data option) :option))

(defclass module-descriptor ()
  ((data :initarg :data :reader %descriptor-data)))

(defun %descriptor (descriptor)
  (unless (typep descriptor 'module-descriptor)
    (%invalid :descriptor "Expected a module descriptor."))
  descriptor)

(defun %clone-descriptor (descriptor)
  (make-instance 'module-descriptor
                 :data (%copy-data (%descriptor-data (%descriptor descriptor))
                                   :descriptor)))

(defun make-module-descriptor (&key id version family title (description "")
                                 authors tags references platforms architectures
                                 options capability provider result-schema
                                 session-types compatible-payloads (lifecycle :current))
  "Construct descriptive metadata only; no handler, payload, or session executes."
  (let* ((normalized-id (%name id :id))
         ;; OPTIONS holds objects, so validate its spine without copying objects.
         (option-list
           (let ((seen (make-hash-table :test #'eq)))
             (loop for tail = options then (cdr tail)
                   while (consp tail)
                   do (when (gethash tail seen) (%invalid :options "Cyclic options."))
                      (setf (gethash tail seen) t)
                   collect (module-option-info (car tail)) into result
                   finally (unless (null tail) (%invalid :options "Expected a proper option list."))
                           (return result))))
         (seen-names (make-hash-table :test #'equal)))
    (dolist (option option-list)
      (let ((name (getf option :name)))
        (when (gethash name seen-names) (%invalid :options "Duplicate option name."))
        (setf (gethash name seen-names) t)))
    (when (and provider (null capability))
      (%invalid :provider "A provider requires a capability."))
    (unless (member lifecycle '(:current :deprecated))
      (%invalid :lifecycle "Expected :CURRENT or :DEPRECATED."))
    (make-instance
     'module-descriptor
     :data (list :schema-version 1 :id normalized-id :version (%text version :version)
                 :family (%name family :family)
                 :title (%text (or title normalized-id) :title t)
                 :description (%text description :description t)
                 :authors (%texts authors :authors) :tags (%metadata-strings tags :tags)
                 :references (%texts references :references)
                 :platforms (%metadata-strings platforms :platforms)
                 :architectures (%metadata-strings architectures :architectures)
                 :options option-list
                 :capability (when capability (%name capability :capability))
                 :provider (when provider (%name provider :provider))
                 :result-schema (%copy-data result-schema :result-schema)
                 :session-types (%metadata-strings session-types :session-types)
                 :compatible-payloads (%names compatible-payloads :compatible-payloads)
                 :lifecycle (%copy-data lifecycle :lifecycle)))))

(defun module-info (descriptor)
  (%copy-data (%descriptor-data (%descriptor descriptor)) :descriptor))

(defclass module-registry ()
  ((entries :initform (make-hash-table :test #'equal) :reader %registry-entries)))

(defun make-module-registry () (make-instance 'module-registry))

(defvar *module-registry* (make-module-registry))

(defun %registry (registry)
  (unless (typep registry 'module-registry)
    (%invalid :registry "Expected a module registry."))
  registry)

(defun %module-key (id version)
  (list (%name id :id) (%text version :version)))

(defun register-module (descriptor &key (registry *module-registry*))
  "Register a snapshot; duplicate exact id/version pairs are rejected."
  (let* ((entries (%registry-entries (%registry registry)))
         (copy (%clone-descriptor descriptor))
         (info (%descriptor-data copy))
         (key (%module-key (getf info :id) (getf info :version))))
    (when (gethash key entries)
      (%invalid :id "This exact module id/version is already registered."))
    (setf (gethash key entries) copy)
    (%clone-descriptor copy)))

(defun unregister-module (id version &key (registry *module-registry*))
  (remhash (%module-key id version) (%registry-entries (%registry registry))))

(defun find-module (id version &key (registry *module-registry*))
  "Find one exact version. There is no implicit latest-version selection."
  (let ((found (gethash (%module-key id version)
                        (%registry-entries (%registry registry)))))
    (when found (%clone-descriptor found))))

(defun %descriptor< (left right)
  (let* ((a (%descriptor-data left)) (b (%descriptor-data right))
         (a-id (getf a :id)) (b-id (getf b :id)))
    (or (string< a-id b-id)
        (and (string= a-id b-id)
             (string< (getf a :version) (getf b :version))))))

(defun list-modules (&key family query tags capability (registry *module-registry*))
  "Return detached descriptors sorted by canonical id, then exact version string.
All requested tags must match; QUERY is a case-insensitive literal substring."
  (let ((family (when family (%name family :family)))
        (capability (when capability (%name capability :capability)))
        (tags (%metadata-strings tags :tags))
        (query (when query (%text query :query t)))
        (entries (%registry-entries (%registry registry)))
        (matches nil))
    (maphash
     (lambda (key descriptor)
       (declare (ignore key))
       (let ((info (%descriptor-data descriptor)))
         (when (and (or (null family) (equal family (getf info :family)))
                    (or (null capability) (equal capability (getf info :capability)))
                    (every (lambda (tag) (member tag (getf info :tags) :test #'string-equal)) tags)
                    (or (null query)
                        (some (lambda (text) (and text (search query text :test #'char-equal)))
                              (append (list (getf info :id) (getf info :version)
                                            (getf info :family) (getf info :title)
                                            (getf info :description) (getf info :capability)
                                            (getf info :provider))
                                      (getf info :tags) (getf info :authors)))))
           (push (%clone-descriptor descriptor) matches))))
     entries)
    (sort matches #'%descriptor<)))

(defun list-module-families (&key (registry *module-registry*))
  "Return built-in families plus registered extensions, sorted and detached."
  (let ((families (mapcar #'copy-seq
                         '("recon" "scan" "fingerprinting" "exploit"
                           "post-exploit" "payload"))))
    (maphash (lambda (key descriptor)
               (declare (ignore key))
               (pushnew (copy-seq (getf (%descriptor-data descriptor) :family))
                        families :test #'equal))
             (%registry-entries (%registry registry)))
    (sort families #'string<)))

(defun module-payload-compatible-p (descriptor payload)
  "Check metadata constraints only. Empty compatibility dimensions are unconstrained."
  (let ((info (%descriptor-data (%descriptor descriptor)))
        (candidate (%descriptor-data (%descriptor payload))))
    (and (equal "payload" (getf candidate :family))
         (or (null (getf info :compatible-payloads))
             (member (getf candidate :id) (getf info :compatible-payloads) :test #'equal))
         (every (lambda (dimension)
                  (let ((left (getf info dimension)) (right (getf candidate dimension)))
                    (or (null left) (null right) (intersection left right :test #'string-equal))))
                '(:platforms :architectures :session-types))
         t)))

(defclass module-instance ()
  ((data :initarg :data :reader %instance-data)))

(defun %option-overrides (options)
  (let ((seen (make-hash-table :test #'equal)))
    (mapcar (lambda (entry)
              (unless (consp entry) (%invalid :options "Expected an option alist entry."))
              (let ((name (%name (car entry) :options)))
                (when (gethash name seen) (%invalid :options "Duplicate option override."))
                (setf (gethash name seen) t)
                (cons name (%copy-data (cdr entry) :options))))
            (%proper-list options :options))))

(defun instantiate-module (descriptor operation-id &key options)
  "Build a validated, operation-scoped instance description without executing it."
  (let* ((info (%descriptor-data (%descriptor descriptor)))
         (operation-id (%text operation-id :operation-id))
         (overrides (%option-overrides options))
         (declared (getf info :options))
         (values nil))
    (dolist (entry overrides)
      (unless (find (car entry) declared :key (lambda (option) (getf option :name))
                    :test #'equal)
        (%invalid :options "Unknown option override.")))
    (dolist (option declared)
      (let* ((name (getf option :name))
             (override (assoc name overrides :test #'equal))
             (present (or override (getf option :default-present-p)))
             (value (if override (cdr override) (getf option :default))))
        (when (and (getf option :required) (not present))
          (%invalid :options "A required option is missing."))
        (when present
          (%check-option-value option value)
          (push (list :name (copy-seq name) :value (%copy-data value :options)
                      :source (if override :instance :default))
                values))))
    (make-instance 'module-instance
                   :data (list :schema-version 1
                               :id (copy-seq (getf info :id))
                               :version (copy-seq (getf info :version))
                               :family (copy-seq (getf info :family))
                               :operation-id operation-id
                               :module (%copy-data info :descriptor)
                               :options (nreverse values)))))

(defun module-instance-info (instance)
  (unless (typep instance 'module-instance)
    (%invalid :instance "Expected a module instance."))
  (%copy-data (%instance-data instance) :instance))
