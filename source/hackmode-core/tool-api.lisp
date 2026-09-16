(in-package :hackmode)

(defstruct tool-target-shape
  name
  description
  predicate
  coercer
  examples
  options)

(defstruct tool-argument
  name
  type
  required-p
  repeatable-p
  default
  flag
  description)

(defstruct tool-mapping
  capability
  provider
  executable
  target-shapes
  arguments
  example-targets
  platforms
  packages
  fixed-arguments
  metadata)

(defstruct tool-command-input
  raw-target
  target
  target-shape
  arguments
  target-options)

(defvar *tool-target-shapes* (make-hash-table :test #'equal)
  "Registered target-shape definitions keyed by canonical name.")

(defvar *tool-mappings* (make-hash-table :test #'equal)
  "Tool metadata keyed by capability/provider pair.")

(defun canonical-tool-name (value)
  (string-downcase (string value)))

(defun tool-mapping-key (capability provider)
  (list (canonical-tool-name capability)
        (canonical-tool-name provider)))

(defun proper-plist-p (value)
  (loop with rest = value
        do (cond
             ((null rest) (return t))
             ((and (consp rest) (consp (cdr rest)))
              (setf rest (cddr rest)))
             (t (return nil)))))

(defun plist-key-present-p (plist key)
  (loop for tail on plist by #'cddr
        thereis (eq (car tail) key)))

(defun normalize-tool-key (value)
  (etypecase value
    (keyword value)
    (symbol (intern (symbol-name value) :keyword))
    (string (intern (string-upcase value) :keyword))))

(defun register-tool-target-shape (name predicate
                                   &key description coercer examples options)
  "Register one reusable tool target shape and return its definition."
  (check-type predicate function)
  (when coercer
    (check-type coercer function))
  (let ((shape
          (make-tool-target-shape
           :name (canonical-tool-name name)
           :description (or description "")
           :predicate predicate
           :coercer (or coercer #'identity)
           :examples (copy-tree examples)
           :options (copy-tree options))))
    (setf (gethash (tool-target-shape-name shape) *tool-target-shapes*) shape)
    shape))

(defun find-tool-target-shape (name)
  "Find target shape NAME, or NIL."
  (gethash (canonical-tool-name name) *tool-target-shapes*))

(defun list-tool-target-shapes ()
  "Return target shapes in stable name order."
  (sort
   (loop for shape being the hash-values of *tool-target-shapes*
         collect shape)
   #'string<
   :key #'tool-target-shape-name))

(defun tool-target-shape-accepts-p (shape value)
  "Return true when SHAPE accepts VALUE."
  (handler-case
      (not (null (funcall (tool-target-shape-predicate shape) value)))
    (condition () nil)))

(defun coerce-tool-target (shape value)
  "Validate VALUE against SHAPE and return the owned provider input value."
  (unless (tool-target-shape-accepts-p shape value)
    (error "Target ~s does not match tool target shape ~a."
           value (tool-target-shape-name shape)))
  (funcall (tool-target-shape-coercer shape) value))

(defmacro define-target-shape (name (&key description examples options coercer)
                               (value)
                               &body predicate-body)
  "Define and register a reusable target shape.

PREDICATE-BODY validates VALUE. COERCER converts accepted external values to the
provider input representation. EXAMPLES and OPTIONS are manifest metadata."
  `(register-tool-target-shape
    ',name
    (lambda (,value) ,@predicate-body)
    :description ,description
    :examples ,examples
    :options ,options
    :coercer ,(if coercer coercer '#'identity)))

(defun make-tool-arg (name type &key required repeatable default flag description)
  "Construct one typed tool argument declaration."
  (make-tool-argument
   :name (normalize-tool-key name)
   :type type
   :required-p (not (null required))
   :repeatable-p (not (null repeatable))
   :default default
   :flag flag
   :description (or description "")))

(defun register-tool-mapping (capability provider
                              &key executable target-shapes arguments
                                example-targets platforms packages
                                fixed-arguments metadata)
  "Register tool metadata for CAPABILITY/PROVIDER without changing its handler."
  (let ((mapping
          (make-tool-mapping
           :capability (canonical-tool-name capability)
           :provider (canonical-tool-name provider)
           :executable (and executable (string executable))
           :target-shapes
           (mapcar #'canonical-tool-name (or target-shapes '(raw)))
           :arguments (copy-list arguments)
           :example-targets (copy-tree example-targets)
           :platforms (mapcar #'string-downcase (mapcar #'string (or platforms '(linux))))
           :packages (copy-tree packages)
           :fixed-arguments (copy-list fixed-arguments)
           :metadata (copy-tree metadata))))
    (dolist (shape-name (tool-mapping-target-shapes mapping))
      (unless (find-tool-target-shape shape-name)
        (error "Tool mapping ~a/~a references unknown target shape ~a."
               capability provider shape-name)))
    (setf (gethash (tool-mapping-key capability provider) *tool-mappings*) mapping)
    mapping))

(defmacro define-tool-mapping ((capability provider) &rest options)
  "Define tool metadata consumed by dynamic tool actors."
  `(register-tool-mapping ,capability ,provider ,@options))

(defun find-tool-mapping (capability provider)
  "Return explicit tool metadata for CAPABILITY/PROVIDER, or NIL."
  (gethash (tool-mapping-key capability provider) *tool-mappings*))

(defun list-tool-mappings ()
  "Return explicit tool mappings in stable capability/provider order."
  (sort
   (loop for mapping being the hash-values of *tool-mappings*
         collect mapping)
   (lambda (left right)
     (let ((left-cap (tool-mapping-capability left))
           (right-cap (tool-mapping-capability right)))
       (or (string< left-cap right-cap)
           (and (string= left-cap right-cap)
                (string< (tool-mapping-provider left)
                         (tool-mapping-provider right))))))))

(defun mapping-target-shapes (mapping)
  (mapcar
   (lambda (name)
     (or (find-tool-target-shape name)
         (error "Unknown target shape ~a." name)))
   (tool-mapping-target-shapes mapping)))

(defun select-tool-target-shape (mapping target &optional requested-shape)
  "Select and return the target shape used for TARGET."
  (let ((shapes (mapping-target-shapes mapping)))
    (if requested-shape
        (let* ((name (canonical-tool-name requested-shape))
               (shape (find name shapes :key #'tool-target-shape-name :test #'string=)))
          (unless shape
            (error "Tool ~a/~a does not accept target shape ~a."
                   (tool-mapping-capability mapping)
                   (tool-mapping-provider mapping)
                   requested-shape))
          (unless (tool-target-shape-accepts-p shape target)
            (error "Target ~s does not match requested shape ~a."
                   target requested-shape))
          shape)
        (or (find-if (lambda (shape)
                       (tool-target-shape-accepts-p shape target))
                     shapes)
            (error "Target ~s matches no shape accepted by ~a/~a."
                   target
                   (tool-mapping-capability mapping)
                   (tool-mapping-provider mapping))))))

(defun argument-definition (mapping key)
  (find (normalize-tool-key key)
        (tool-mapping-arguments mapping)
        :key #'tool-argument-name
        :test #'eq))

(defun normalize-tool-arguments (mapping values)
  "Validate tool argument plist VALUES and materialize declared defaults."
  (unless (proper-plist-p values)
    (error "Tool arguments must be a property list, got ~s." values))
  (loop for (key value) on values by #'cddr
        unless (argument-definition mapping key)
          do (error "Unknown argument ~s for ~a/~a."
                    key
                    (tool-mapping-capability mapping)
                    (tool-mapping-provider mapping))
        else do
          (let ((definition (argument-definition mapping key)))
            (if (tool-argument-repeatable-p definition)
                (unless (and (listp value)
                             (every (lambda (item)
                                      (typep item (tool-argument-type definition)))
                                    value))
                  (error "Argument ~s requires a list of ~s values."
                         key (tool-argument-type definition)))
                (unless (typep value (tool-argument-type definition))
                  (error "Argument ~s requires type ~s, got ~s."
                         key
                         (tool-argument-type definition)
                         (type-of value))))))
  (let ((result (copy-list values)))
    (dolist (definition (tool-mapping-arguments mapping))
      (let ((name (tool-argument-name definition)))
        (cond
          ((plist-key-present-p result name) nil)
          ((tool-argument-required-p definition)
           (error "Required tool argument ~s is missing." name))
          ((not (null (tool-argument-default definition)))
           (setf (getf result name) (tool-argument-default definition))))))
    result))

(defun validate-target-options (shape values)
  "Validate target-option plist VALUES declared by SHAPE."
  (unless (proper-plist-p values)
    (error "Target options must be a property list, got ~s." values))
  (let ((definitions (tool-target-shape-options shape)))
    (loop for (key value) on values by #'cddr
          for definition =
            (find (normalize-tool-key key) definitions
                  :key #'tool-argument-name :test #'eq)
          unless definition
            do (error "Unknown target option ~s for shape ~a."
                      key (tool-target-shape-name shape))
          else do
            (unless (typep value (tool-argument-type definition))
              (error "Target option ~s requires type ~s."
                     key (tool-argument-type definition)))))
  (copy-list values))

(defun make-validated-tool-command-input (mapping target
                                          &key arguments target-options target-shape)
  "Validate an external tool invocation and return its owned command input."
  (let* ((shape (select-tool-target-shape mapping target target-shape))
         (coerced (coerce-tool-target shape target)))
    (make-tool-command-input
     :raw-target target
     :target coerced
     :target-shape (tool-target-shape-name shape)
     :arguments (normalize-tool-arguments mapping (or arguments nil))
     :target-options (validate-target-options shape (or target-options nil)))))

(defun executable-available-p (program)
  "Return true when PROGRAM resolves on the current PATH."
  (and program
       (ignore-errors
         (not (null (uiop:find-program-pathname program))))))

(defun kali-linux-p ()
  "Return true when /etc/os-release identifies Kali Linux."
  (handler-case
      (let ((text (uiop:read-file-string #P"/etc/os-release")))
        (not (null (cl-ppcre:scan "(?m)^ID=kali$" text))))
    (condition () nil)))

(defun tool-mapping-available-p (mapping)
  "Return true when MAPPING's executable is currently runnable."
  (or (null (tool-mapping-executable mapping))
      (executable-available-p (tool-mapping-executable mapping))))

(defun domain-target-p (value)
  (or (typep value 'domain)
      (and (stringp value)
           (cl-ppcre:scan
            "^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z]{2,63}$"
            value))))

(defun host-target-p (value)
  (or (typep value 'host)
      (and (stringp value)
           (or (cl-ppcre:scan
                "^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$"
                value)
               (and (find #\: value)
                    (not (find #\/ value)))))))

(defun network-target-p (value)
  (and (stringp value)
       (cl-ppcre:scan "^[0-9A-Fa-f:.]+/[0-9]{1,3}$" value)))

(defun url-target-p (value)
  (or (typep value 'url)
      (and (stringp value)
           (cl-ppcre:scan "^https?://" value))))

(defun coerce-domain-target (value)
  (if (typep value 'domain)
      value
      (make-instance 'domain :record (string-downcase value))))

(defun coerce-host-target (value)
  (if (typep value 'host)
      value
      (make-instance 'host :ip value)))

(defun coerce-url-target (value)
  (if (typep value 'url)
      value
      (multiple-value-bind (scheme ignored host port path query)
          (quri:parse-uri value)
        (declare (ignore ignored))
        (make-instance 'url
                       :scheme (or scheme "http")
                       :host (or host "")
                       :port (or port (if (and scheme (string= scheme "https")) 443 80))
                       :path (or path "")
                       :query (or query "")))))

(define-target-shape domain
    (:description "DNS domain name"
     :examples '("example.org" "sub.example.org")
     :coercer #'coerce-domain-target)
    (value)
  (domain-target-p value))

(define-target-shape host
    (:description "IPv4 or IPv6 host address"
     :examples '("192.0.2.10" "2001:db8::10")
     :coercer #'coerce-host-target)
    (value)
  (host-target-p value))

(define-target-shape network
    (:description "IPv4 or IPv6 CIDR network"
     :examples '("192.0.2.0/24" "2001:db8::/32"))
    (value)
  (network-target-p value))

(define-target-shape url
    (:description "HTTP or HTTPS URL"
     :examples '("https://example.org/" "http://192.0.2.10:8080/")
     :coercer #'coerce-url-target)
    (value)
  (url-target-p value))

(define-target-shape raw
    (:description "Opaque string target"
     :examples '("example-target"))
    (value)
  (stringp value))
