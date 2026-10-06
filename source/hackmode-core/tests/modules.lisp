(defpackage :hackmode-module-tests
  (:use :cl)
  (:export :run-module-tests))

(in-package :hackmode-module-tests)

(defun check (condition format-control &rest format-arguments)
  (unless condition
    (error (apply #'format nil format-control format-arguments))))

(defun check-equal (expected actual description)
  (check (equal expected actual) "~A: expected ~S, got ~S."
         description expected actual))

(defmacro expect-validation (description &body body)
  `(let ((condition
           (handler-case
               (progn ,@body nil)
             (hackmode-modules:module-validation-error (condition)
               condition))))
     (check condition "~A must signal MODULE-VALIDATION-ERROR." ,description)
     (check (hackmode-modules:module-error-field condition)
            "~A must identify the invalid field." ,description)
     (check (hackmode-modules:module-error-reason condition)
            "~A must explain the validation failure." ,description)
     condition))

(defun descriptor (&rest initargs)
  (apply #'hackmode-modules:make-module-descriptor
         (append initargs
                 (list :id "test/probe" :version "1.0" :family :recon
                       :title "Local test probe"
                       :description "A deterministic catalog fixture."
                       :authors '("Catalog tests")
                       :tags '("test" "local")
                       :references '("urn:hackmode:test:probe")
                       :platforms nil :architectures nil :options nil
                       :capability :probe :provider :local
                       :result-schema '(:type :object)
                       :session-types nil :compatible-payloads nil
                       :lifecycle :current))))

(defun option (name type &rest initargs)
  (apply #'hackmode-modules:make-module-option
         :name name :type type :description "Test option" initargs))

(defun infos (modules)
  (mapcar #'hackmode-modules:module-info modules))

(defun identities (modules)
  (mapcar (lambda (module)
            (let ((info (hackmode-modules:module-info module)))
              (list (getf info :id) (getf info :version))))
          modules))

(defun instance-options (module &optional options)
  (mapcar (lambda (entry) (cons (getf entry :name) (getf entry :value)))
          (getf (hackmode-modules:module-instance-info
                 (hackmode-modules:instantiate-module
                  module "operation-test" :options options))
                :options)))

(defun effective-option (name info)
  (find name (getf info :options) :test #'equal
        :key (lambda (entry) (getf entry :name))))

(defun run-descriptor-tests ()
  (let* ((module (descriptor :id :test/probe :family :scan
                             :capability :probe :provider :local))
         (info (hackmode-modules:module-info module)))
    (check (typep module 'hackmode-modules:module-descriptor)
           "Constructor must return a typed descriptor.")
    (check-equal 1 (getf info :schema-version) "Descriptor schema version")
    (check-equal "test/probe" (getf info :id) "Canonical descriptor ID")
    (check-equal "scan" (getf info :family) "Canonical family")
    (check-equal "probe" (getf info :capability) "Canonical capability")
    (check-equal "local" (getf info :provider) "Canonical provider")
    (dolist (key '(:id :version :family :title :description :authors :tags
                   :references :platforms :architectures :options :capability
                   :provider :result-schema :session-types
                   :compatible-payloads :lifecycle))
      (check (not (eq :missing (getf info key :missing)))
             "Descriptor info must retain the ~S field." key)))
  (dolist (family '(recon scan fingerprinting exploit post-exploit payload
                   custom-inspection))
    (check-equal (string-downcase (symbol-name family))
                 (getf (hackmode-modules:module-info
                        (descriptor :family family)) :family)
                 "Built-in and extension families"))
  (check-equal "vendor/probe@host+v1.2_x-y"
               (getf (hackmode-modules:module-info
                      (descriptor :id "Vendor/Probe@Host+V1.2_X-Y")) :id)
               "Permitted identifier punctuation")
  (check-equal "Build-A+17"
               (getf (hackmode-modules:module-info
                      (descriptor :version "Build-A+17")) :version)
               "Versions must retain their exact spelling")
  (check-equal :current
               (getf (hackmode-modules:module-info
                      (hackmode-modules:make-module-descriptor
                       :id "default-lifecycle" :version "1" :family :recon))
                     :lifecycle)
               "Descriptors default to the current lifecycle")
  (dolist (lifecycle '(:current :deprecated))
    (check-equal lifecycle
                 (getf (hackmode-modules:module-info
                        (descriptor :lifecycle lifecycle)) :lifecycle)
                 "Supported descriptor lifecycle"))
  (dolist (lifecycle '(nil :unknown (:prepare :local)))
    (expect-validation "Unsupported descriptor lifecycle"
      (descriptor :lifecycle lifecycle)))
  (dolist (initargs '((:id "") (:id "bad id") (:id "bad:id")
                      (:family "bad family") (:provider "bad provider")
                      (:capability "bad capability") (:version "")
                      (:version :one) (:capability nil :provider "local")))
    (expect-validation "Invalid descriptor metadata"
      (apply #'descriptor initargs)))
  t)

(defun run-registry-tests ()
  (let ((registry (hackmode-modules:make-module-registry)))
    (check (typep registry 'hackmode-modules:module-registry)
           "Constructor must return a typed registry.")
    (check (null (hackmode-modules:list-modules :registry registry))
           "A fresh registry must contain no descriptors.")
    (let ((families (hackmode-modules:list-module-families :registry registry)))
      (dolist (family '("recon" "scan" "fingerprinting" "exploit"
                        "post-exploit" "payload"))
        (check (member family families :test #'equal)
               "The empty catalog must advertise family ~S." family)))
    (dolist (module (list (descriptor :id "zeta" :version "1")
                          (descriptor :id "alpha" :version "2")
                          (descriptor :id "alpha" :version "10")
                          (descriptor :id "alpha" :version "1"
                                      :family :custom-z
                                      :title "Distinctive catalog needle"
                                      :tags '("focused" "local"))
                          (descriptor :id "beta" :version "1"
                                      :family :custom-a :capability :inspect)))
      (hackmode-modules:register-module module :registry registry))
    (check-equal '(("alpha" "1") ("alpha" "10") ("alpha" "2")
                   ("beta" "1") ("zeta" "1"))
                 (identities (hackmode-modules:list-modules :registry registry))
                 "Deterministic ID and exact-version ordering")
    (check (hackmode-modules:find-module :alpha "10" :registry registry)
           "ID lookup must normalize symbols.")
    (check (null (hackmode-modules:find-module "alpha" "1.0"
                                             :registry registry))
           "Lookup must not coerce distinct version strings.")
    (check (null (hackmode-modules:find-module "missing" "1"
                                             :registry registry))
           "Unknown module must return NIL.")
    (expect-validation "Duplicate registration"
      (hackmode-modules:register-module
       (descriptor :id "ALPHA" :version "1") :registry registry))
    (check-equal "Distinctive catalog needle"
                 (getf (hackmode-modules:module-info
                        (hackmode-modules:find-module "alpha" "1"
                                                     :registry registry))
                       :title)
                 "Rejected duplicates must retain the original descriptor")
    (check-equal '(("alpha" "1"))
                 (identities (hackmode-modules:list-modules
                              :query "NEEDLE" :registry registry))
                 "Case-insensitive metadata search")
    (check-equal '(("alpha" "1"))
                 (identities (hackmode-modules:list-modules
                              :family :custom-z :tags '("focused")
                              :capability :probe :registry registry))
                 "Combined family, tag, and capability filters")
    (check-equal '(("beta" "1"))
                 (identities (hackmode-modules:list-modules
                              :capability :inspect :registry registry))
                 "Capability filtering")
    (check (null (hackmode-modules:list-modules
                  :tags '("absent-tag") :registry registry))
           "Unmatched tags must not return unrelated descriptors.")
    (check (null (hackmode-modules:list-modules
                  :tags '("focused" "absent-tag") :registry registry))
           "Every requested tag must match.")
    (let ((families (hackmode-modules:list-module-families :registry registry)))
      (check (member "custom-a" families :test #'equal)
             "Registered extension family must be discoverable.")
      (check (member "custom-z" families :test #'equal)
             "Every registered extension family must be discoverable.")
      (check-equal families
                   (hackmode-modules:list-module-families :registry registry)
                   "Family discovery must be deterministic")
      (check-equal (sort (copy-list families) #'string<) families
                   "All advertised families must be sorted")
      (check-equal '("custom-a" "custom-z")
                   (remove-if-not
                    (lambda (family) (member family '("custom-a" "custom-z")
                                             :test #'equal))
                    families)
                   "Extension families must be sorted"))
    (hackmode-modules:unregister-module :alpha "10" :registry registry)
    (check (null (hackmode-modules:find-module "alpha" "10"
                                             :registry registry))
           "Unregister must remove only the exact ID/version.")
    (check (hackmode-modules:find-module "alpha" "1" :registry registry)
           "Unregister must retain other versions.")
    (hackmode-modules:register-module
     (descriptor :id "case-sensitive" :version "Build-A") :registry registry)
    (check (null (hackmode-modules:find-module "case-sensitive" "build-a"
                                             :registry registry))
           "Exact version lookup must remain case-sensitive.")
    (check (hackmode-modules:find-module "case-sensitive" "Build-A"
                                       :registry registry)
           "Exact original version must remain retrievable.")
    (let ((hackmode-modules:*module-registry* registry))
      (check-equal (identities (hackmode-modules:list-modules :registry registry))
                   (identities (hackmode-modules:list-modules))
                   "The dynamically selected registry must be honored")))
  t)

(defun run-metadata-string-tests ()
  (let* ((tags '("Mixed Case / Evidence!" "Network: TLS"))
         (platforms '("Linux / Native"))
         (architectures '("X86-64 / Native"))
         (session-types '("Shell over TLS"))
         (module (descriptor :tags tags :platforms platforms
                             :architectures architectures
                             :session-types session-types))
         (info (hackmode-modules:module-info module))
         (registry (hackmode-modules:make-module-registry)))
    (check-equal tags (getf info :tags) "Tags preserve exact display text")
    (check-equal platforms (getf info :platforms)
                 "Platforms preserve exact display text")
    (check-equal architectures (getf info :architectures)
                 "Architectures preserve exact display text")
    (check-equal session-types (getf info :session-types)
                 "Session types preserve exact display text")
    (hackmode-modules:register-module module :registry registry)
    (check-equal '(("test/probe" "1.0"))
                 (identities (hackmode-modules:list-modules
                              :tags '("mixed case / evidence!" "NETWORK: TLS")
                              :registry registry))
                 "Tag matching is case-insensitive without rewriting tag data")
    (check (hackmode-modules:module-payload-compatible-p
            module (descriptor :id "payload/mixed" :family :payload
                               :platforms '("linux / native")
                               :architectures '("x86-64 / native")
                               :session-types '("shell OVER tls")))
           "Compatibility dimensions match case-insensitively without rewriting data."))
  (dolist (field '(:tags :platforms :architectures :session-types))
    (expect-validation "Metadata string lists reject symbols"
      (apply #'descriptor (list field '(:symbol))))
    (expect-validation "Metadata string lists reject empty strings"
      (apply #'descriptor (list field '("")))))
  (let ((registry (hackmode-modules:make-module-registry)))
    (expect-validation "Tag filters reject symbols"
      (hackmode-modules:list-modules :tags '(:symbol) :registry registry))
    (expect-validation "Tag filters reject empty strings"
      (hackmode-modules:list-modules :tags '("") :registry registry)))
  t)

(defun run-option-tests ()
  (let* ((flag (option :enabled :boolean :required t :default nil
                       :default-present-p t))
         (flag-info (hackmode-modules:module-option-info flag))
         (module (descriptor
                  :options (list flag
                                 (option :label :string :default "default-label"
                                         :default-present-p t)
                                 (option :count :integer :default 0
                                         :default-present-p t)
                                 (option :omitted :string)))))
    (check (typep flag 'hackmode-modules:module-option)
           "Constructor must return a typed option.")
    (check-equal "enabled" (getf flag-info :name) "Canonical option name")
    (check-equal :boolean (getf flag-info :type) "Option type")
    (check (getf flag-info :required) "Required option metadata must persist.")
    (check (getf flag-info :default-present-p)
           "An explicit false default must count as present.")
    (check (null (getf flag-info :default)) "False defaults must remain NIL.")
    (let ((values (instance-options module)))
      (check (assoc "enabled" values :test #'equal)
             "Required false defaults must produce an option entry.")
      (check (null (cdr (assoc "enabled" values :test #'equal)))
             "Required false defaults must retain NIL.")
      (check-equal "default-label" (cdr (assoc "label" values :test #'equal))
                   "String default")
      (check-equal 0 (cdr (assoc "count" values :test #'equal))
                   "Zero integer default")
      (check (null (assoc "omitted" values :test #'equal))
             "Absent optional options without defaults must be omitted."))
    (let ((values (instance-options module '((:enabled . nil)
                                             ("LABEL" . "supplied")))))
      (check (assoc "enabled" values :test #'equal)
             "Explicit false must not be confused with an absent option.")
      (check (null (cdr (assoc "enabled" values :test #'equal)))
             "Explicit false must survive normalization.")
      (check-equal "supplied" (cdr (assoc "label" values :test #'equal))
                   "Explicit input must override a default"))
    (let ((info (hackmode-modules:module-instance-info
                 (hackmode-modules:instantiate-module
                  module "operation-sources" :options '((:enabled . nil))))))
      (check-equal '(:name "enabled" :value nil :source :instance)
                   (effective-option "enabled" info)
                   "Explicit false values retain instance provenance")
      (check-equal '(:name "count" :value 0 :source :default)
                   (effective-option "count" info)
                   "Effective defaults retain default provenance")
      (check-equal '(:name "label" :value "default-label" :source :default)
                   (effective-option "label" info)
                   "Effective string defaults retain default provenance"))
    (expect-validation "Duplicate supplied option names"
      (instance-options module '((:enabled . t) ("ENABLED" . nil))))
    (expect-validation "Unknown supplied option"
      (instance-options module '(("unknown" . "value"))))
    (expect-validation "Non-alist supplied options"
      (instance-options module '("enabled" t))))
  (expect-validation "Missing required option"
    (instance-options (descriptor :options (list (option :target :string
                                                          :required t)))))
  (expect-validation "Duplicate descriptor option names"
    (descriptor :options (list (option :target :string)
                               (option "TARGET" :string))))
  (expect-validation "Invalid default type"
    (option :count :integer :default "three" :default-present-p t))
  (expect-validation "Unsupported option type"
    (option :untyped :function))
  (expect-validation "Invalid option name"
    (option "bad option" :string))
  (let* ((implicit-false (option :enabled :boolean :default nil))
         (suppressed (option :label :string :default "unused"
                             :default-present-p nil))
         (values (instance-options (descriptor :options (list implicit-false
                                                                suppressed)))))
    (check (assoc "enabled" values :test #'equal)
           "Explicit NIL defaults must be detected when presence is inferred.")
    (check (null (assoc "label" values :test #'equal))
           "Explicitly absent defaults must not leak into instance options."))
  (dolist (case (list (list :string "text" 17)
                     (list :integer -3 "3")
                     (list :boolean t "false")
                     (list :string-list '("one" "two") '("one" 2))
                     (list :asset-reference "asset:unresolved-17" "")
                     (list :path "/path/not-required-to-exist" "")
                     (list :credential-reference "credential:unresolved-17" "")))
    (destructuring-bind (type valid invalid) case
      (let* ((module (descriptor :options (list (option :value type))))
             (values (instance-options module (list (cons :value valid)))))
        (check-equal valid (cdr (assoc "value" values :test #'equal))
                     (format nil "Valid ~S option" type))
        (expect-validation (format nil "Invalid ~S option" type)
          (instance-options module (list (cons :value invalid)))))))
  (let* ((choice (cons :route (cons "literal" "tail")))
         (module (descriptor
                  :options (list (option :mode :enum
                                         :choices (list :fast nil choice))))))
    (dolist (value (list :fast nil (cons :route (cons "literal" "tail"))))
      (check-equal value
                   (cdr (assoc "mode"
                               (instance-options module (list (cons :mode value)))
                               :test #'equal))
                   "Enum choices preserve keyword, NIL, and dotted data"))
    (expect-validation "Enum values outside the choice set"
      (instance-options module '((:mode . :slow)))))
  (let ((module (descriptor :options (list (option :value :boolean)))))
    (expect-validation "Boolean options reject integers"
      (instance-options module '((:value . 0)))))
  t)

(defun run-copy-isolation-tests ()
  (let* ((id (copy-seq "copy/probe"))
         (version (copy-seq "Version-A"))
         (author (copy-seq "Original author"))
         (tag (copy-seq "original"))
         (schema-text (copy-seq "schema-value"))
         (schema-tail (copy-seq "schema-tail"))
         (schema (list :nested (cons schema-text schema-tail)))
         (choice-text (copy-seq "choice-value"))
         (choice-tail (copy-seq "choice-tail"))
         (choice (cons choice-text choice-tail))
         (definition (option :mode :enum :choices (list choice)
                             :default choice :default-present-p t))
         (module (descriptor :id id :version version :authors (list author)
                             :tags (list tag) :result-schema schema
                             :options (list definition)))
         (registry (hackmode-modules:make-module-registry)))
    (setf (char id 0) #\X
          (char version 0) #\X
          (char author 0) #\X
          (char tag 0) #\X
          (char schema-text 0) #\X
          (char schema-tail 0) #\X
          (char choice-text 0) #\X
          (char choice-tail 0) #\X)
    (let* ((info (hackmode-modules:module-info module))
           (option-info (first (getf info :options))))
      (check-equal "copy/probe" (getf info :id) "Copied descriptor ID input")
      (check-equal "Version-A" (getf info :version) "Copied version input")
      (check-equal '("Original author") (getf info :authors) "Copied authors")
      (check-equal '("original") (getf info :tags) "Copied tags")
      (check-equal '(:nested ("schema-value" . "schema-tail"))
                   (getf info :result-schema) "Copied dotted schema data")
      (check-equal '("choice-value" . "choice-tail")
                   (getf option-info :default) "Copied dotted default data")
      (setf (char (getf info :id) 0) #\Y
            (char (first (getf info :authors)) 0) #\Y
            (char (car (getf (getf info :result-schema) :nested)) 0) #\Y
            (char (cdr (getf (getf info :result-schema) :nested)) 0) #\Y
            (char (car (getf option-info :default)) 0) #\Y
            (char (cdr (getf option-info :default)) 0) #\Y))
    (let ((info (hackmode-modules:module-info module)))
      (check-equal "copy/probe" (getf info :id) "Descriptor info ID isolation")
      (check-equal '("Original author") (getf info :authors)
                   "Descriptor info author isolation")
      (check-equal '(:nested ("schema-value" . "schema-tail"))
                   (getf info :result-schema) "Descriptor info dotted isolation")
      (check-equal '("choice-value" . "choice-tail")
                   (getf (first (getf info :options)) :default)
                   "Descriptor option info isolation"))
    (let ((info (hackmode-modules:module-option-info definition)))
      (setf (char (car (first (getf info :choices))) 0) #\Z
            (char (cdr (first (getf info :choices))) 0) #\Z)
      (check-equal '(("choice-value" . "choice-tail"))
                   (getf (hackmode-modules:module-option-info definition) :choices)
                   "Option choice accessor isolation"))
    (hackmode-modules:register-module module :registry registry)
    (let ((found (hackmode-modules:find-module "copy/probe" "Version-A"
                                             :registry registry)))
      (check (not (eq module found))
             "Registration and lookup must not expose the caller's descriptor.")
      (check (not (eq found (hackmode-modules:find-module
                            "copy/probe" "Version-A" :registry registry)))
             "Each lookup must return a fresh descriptor snapshot.")
      (let ((info (hackmode-modules:module-info found)))
        (setf (char (getf info :version) 0) #\Z
              (char (cdr (getf (getf info :result-schema) :nested)) 0) #\Z)))
    (let ((listed (first (hackmode-modules:list-modules :registry registry))))
      (check (not (eq module listed))
             "Listing must not return the registered input descriptor.")
      (check-equal '(:nested ("schema-value" . "schema-tail"))
                   (getf (hackmode-modules:module-info listed) :result-schema)
                   "Registry metadata isolation"))
    (let* ((operation-id (copy-seq "operation-copy"))
           (supplied (cons (copy-seq "choice-value") (copy-seq "choice-tail")))
           (instance (hackmode-modules:instantiate-module
                      module operation-id :options (list (cons :mode supplied)))))
      (check (typep instance 'hackmode-modules:module-instance)
             "Instantiation must return a typed instance.")
      (setf (char operation-id 0) #\X
            (char (car supplied) 0) #\X
            (char (cdr supplied) 0) #\X)
      (let* ((info (hackmode-modules:module-instance-info instance))
             (value (getf (effective-option "mode" info) :value)))
        (check-equal 1 (getf info :schema-version) "Instance schema version")
        (check-equal "copy/probe" (getf info :id) "Instance descriptor ID")
        (check-equal "Version-A" (getf info :version) "Instance exact version")
        (check-equal "recon" (getf info :family) "Instance family")
        (check-equal (hackmode-modules:module-info module) (getf info :module)
                     "Instance retains the complete descriptor snapshot")
        (check-equal "operation-copy" (getf info :operation-id)
                     "Instance operation input isolation")
        (check-equal '("choice-value" . "choice-tail") value
                     "Instance options input isolation")
        (setf (char (getf info :operation-id) 0) #\Y
              (char (car value) 0) #\Y
              (char (cdr value) 0) #\Y
              (char (getf (getf info :module) :id) 0) #\Y
              (char (cdr (getf (getf (getf info :module) :result-schema)
                               :nested)) 0) #\Y))
      (let ((info (hackmode-modules:module-instance-info instance)))
        (check-equal "operation-copy" (getf info :operation-id)
                     "Instance operation output isolation")
        (check-equal '("choice-value" . "choice-tail")
                     (getf (effective-option "mode" info) :value)
                     "Instance dotted option output isolation")
        (check-equal (hackmode-modules:module-info module) (getf info :module)
                     "Instance descriptor snapshot output isolation"))))
  t)

(defun run-payload-compatibility-tests ()
  (let* ((module (descriptor :family :exploit
                             :compatible-payloads '("Payload/Shell")
                             :platforms '("linux") :architectures '("x86-64")
                             :session-types '("shell")))
         (payload (descriptor :id "PAYLOAD/SHELL" :family :payload
                              :platforms '("linux") :architectures '("x86-64")
                              :session-types '("shell"))))
    (check (hackmode-modules:module-payload-compatible-p module payload)
           "Payload IDs normalize and intersecting constraints must match.")
    (dolist (initargs '((:id "payload/other") (:family :scan)
                        (:platforms ("windows")) (:architectures ("arm64"))
                        (:session-types ("meterpreter"))))
      (let ((other (apply #'descriptor
                          (append initargs
                                  '(:id "payload/shell" :family :payload
                                    :platforms ("linux")
                                    :architectures ("x86-64")
                                    :session-types ("shell"))))))
        (check (not (hackmode-modules:module-payload-compatible-p module other))
               "Incompatible payload constraint ~S must be rejected." initargs)))
    (check (hackmode-modules:module-payload-compatible-p
            module (descriptor :id "payload/shell" :family :payload))
           "Unconstrained payload dimensions must not reject a valid ID.")
    (check (hackmode-modules:module-payload-compatible-p
            (descriptor :family :exploit) payload)
           "Unconstrained descriptors must accept a payload family member.")
    (check (not (hackmode-modules:module-payload-compatible-p
                 (descriptor :family :exploit) (descriptor :family :recon)))
           "Unconstrained descriptors still require the payload family."))
  t)

(defun catalog-info (registry command &rest initargs)
  (hackmode-modules:module-catalog-result-info
   (hackmode-modules:handle-module-catalog-request
    (apply #'hackmode-modules:make-module-catalog-request
           :request-id "request-test" :operation-id "operation-test"
           :command command initargs)
    :registry registry)))

(defun run-catalog-request-tests ()
  (let* ((registry (hackmode-modules:make-module-registry))
         (module (descriptor :options (list (option :enabled :boolean)
                                            (option :label :string)))))
    (hackmode-modules:register-module module :registry registry)
    (dolist (command '(:families :list :describe :instantiate))
      (let ((info (catalog-info registry command :id "test/probe" :version "1.0"
                                :options '((:enabled . nil)))))
        (check-equal "request-test" (getf info :request-id)
                     "Catalog request correlation")
        (check-equal "operation-test" (getf info :operation-id)
                     "Catalog operation correlation")
        (check-equal :ok (getf info :status) "Successful catalog status")))
    (check-equal (hackmode-modules:list-module-families :registry registry)
                 (getf (catalog-info registry :families) :value)
                 "Family request and direct API parity")
    (check-equal (infos (hackmode-modules:list-modules :registry registry))
                 (getf (catalog-info registry :list) :value)
                 "List request and direct API parity")
    (check-equal (infos (hackmode-modules:list-modules
                        :family :recon :query "probe" :tags '("test")
                        :capability :probe :registry registry))
                 (getf (catalog-info registry :list :family :recon :query "probe"
                                     :tags '("test") :capability :probe) :value)
                 "Filtered list request and direct API parity")
    (check-equal (hackmode-modules:module-info module)
                 (getf (catalog-info registry :describe
                                     :id "test/probe" :version "1.0") :value)
                 "Describe request and direct API parity")
    (check-equal (hackmode-modules:module-instance-info
                  (hackmode-modules:instantiate-module
                   module "operation-test" :options '((:enabled . nil))))
                 (getf (catalog-info registry :instantiate
                                     :id "test/probe" :version "1.0"
                                     :options '((:enabled . nil))) :value)
                 "Instantiation request and direct API parity")
    (dolist (command '(:describe :instantiate))
      (let ((info (catalog-info registry command :id "absent" :version "1")))
        (check-equal :not-found (getf info :status) "Missing module status")
        (check-equal "request-test" (getf info :request-id)
                     "Not-found correlation must persist")
        (check-equal "operation-test" (getf info :operation-id)
                     "Not-found operation correlation must persist")))
    (let ((info (catalog-info registry :instantiate
                              :id "test/probe" :version "1.0"
                              :options '((:enabled . "false")))))
      (check-equal :invalid-request (getf info :status)
                   "Invalid option input must produce a typed catalog failure")
      (check-equal "request-test" (getf info :request-id)
                   "Validation failure request correlation")
      (check-equal "operation-test" (getf info :operation-id)
                   "Validation failure operation correlation"))
    (let ((result (hackmode-modules:handle-module-catalog-request
                   '(:command :list) :registry registry)))
      (check (typep result 'hackmode-modules:module-catalog-result)
             "Invalid input must produce a typed catalog result.")
      (check-equal :invalid-request
                   (getf (hackmode-modules:module-catalog-result-info result) :status)
                   "Non-request objects must be rejected"))
    (expect-validation "Unknown catalog command"
      (hackmode-modules:make-module-catalog-request
       :request-id "invalid-command" :command :run))
    (expect-validation "Absent catalog command"
      (hackmode-modules:make-module-catalog-request :request-id "absent-command"))
    (expect-validation "Absent request identity"
      (hackmode-modules:make-module-catalog-request :command :list))
    (expect-validation "Empty request identity"
      (hackmode-modules:make-module-catalog-request :request-id "" :command :list))
    (expect-validation "Instantiation requests require operation identity"
      (hackmode-modules:make-module-catalog-request
       :request-id "missing-operation" :command :instantiate
       :id "test/probe" :version "1.0"))
    (let* ((request-id (copy-seq "request-copy"))
           (operation-id (copy-seq "operation-copy"))
           (request (hackmode-modules:make-module-catalog-request
                     :request-id request-id :operation-id operation-id
                     :command :describe :id "test/probe" :version "1.0")))
      (check (typep request 'hackmode-modules:module-catalog-request)
             "Request constructor must return a typed request.")
      (setf (char request-id 0) #\X (char operation-id 0) #\X)
      (let* ((result (hackmode-modules:handle-module-catalog-request
                      request :registry registry))
             (info (hackmode-modules:module-catalog-result-info result)))
        (check-equal "request-copy" (getf info :request-id)
                     "Request input correlation isolation")
        (check-equal "operation-copy" (getf info :operation-id)
                     "Request input operation isolation")
        (setf (char (getf info :request-id) 0) #\Y
              (char (getf info :operation-id) 0) #\Y
              (char (getf (getf info :value) :id) 0) #\Y)
        (let ((fresh (hackmode-modules:module-catalog-result-info result)))
          (check-equal "request-copy" (getf fresh :request-id)
                       "Result correlation output isolation")
          (check-equal "operation-copy" (getf fresh :operation-id)
                       "Result operation output isolation")
          (check-equal "test/probe" (getf (getf fresh :value) :id)
                       "Result descriptor output isolation"))))
    (let* ((id (copy-seq "test/probe"))
           (version (copy-seq "1.0"))
           (name (copy-seq "label"))
           (value (copy-seq "copied-request-value"))
           (overrides (list (cons name value)))
           (request (hackmode-modules:make-module-catalog-request
                     :request-id "copy-options" :operation-id "operation-test"
                     :command :instantiate :id id :version version
                     :options overrides)))
      (setf (char id 0) #\X (char version 0) #\X
            (char name 0) #\X (char value 0) #\X
            (car overrides) (cons :unknown "replacement"))
      (let ((info (hackmode-modules:module-catalog-result-info
                   (hackmode-modules:handle-module-catalog-request
                    request :registry registry))))
        (check-equal :ok (getf info :status) "Request identity input isolation")
        (check-equal '(:name "label" :value "copied-request-value" :source :instance)
                     (effective-option "label" (getf info :value))
                     "Request options input isolation")))
    (let ((replies nil)
          (request (hackmode-modules:make-module-catalog-request
                    :request-id "receiver-request" :operation-id "receiver-operation"
                    :command :describe :id "test/probe" :version "1.0")))
      (let ((receiver (hackmode-modules:make-module-catalog-receiver
                       :registry registry :reply (lambda (result) (push result replies)))))
        (let ((returned (funcall receiver request)))
          (check (typep returned 'hackmode-modules:module-catalog-result)
                 "Receiver must return a typed result.")
          (check (not (eq returned (first replies)))
                 "Callback result and returned result must be detached."))
        (check-equal 1 (length replies) "Receiver must send one correlated reply")
        (check-equal
         (hackmode-modules:module-catalog-result-info
          (hackmode-modules:handle-module-catalog-request request :registry registry))
         (hackmode-modules:module-catalog-result-info (first replies))
         "Receiver and direct request handling parity"))))
  t)

(defun run-malformed-request-tests ()
  (let ((registry (hackmode-modules:make-module-registry)))
    (labels ((invalid-result (request description)
               (let ((result (hackmode-modules:handle-module-catalog-request
                              request :registry registry)))
                 (check (typep result 'hackmode-modules:module-catalog-result)
                        "~A must return a typed catalog result." description)
                 (let ((info (hackmode-modules:module-catalog-result-info result)))
                   (check-equal :invalid-request (getf info :status) description)
                   (check (getf (getf info :value) :field)
                          "~A must retain a validation field." description)
                   (check (getf (getf info :value) :reason)
                          "~A must retain a validation reason." description)))))
      (invalid-result (make-instance 'hackmode-modules:module-catalog-request)
                      "Uninitialized catalog request")
      (dolist (case '(("Request data missing correlation" (:command :list))
                      ("Duplicate request field"
                       (:request-id "first" :request-id "second" :command :list))
                      ("Odd request property list"
                       (:request-id "odd" :command))
                      ("Dotted request property list"
                       (:request-id "dotted" :command . :list))
                      ("Unknown request field"
                       (:request-id "unknown-key" :command :list :unexpected t))
                      ("Unknown request command"
                       (:request-id "unknown-command" :command :run))
                      ("Malformed request correlation"
                       (:request-id 17 :command :list))))
        (invalid-result
         (make-instance 'hackmode-modules:module-catalog-request :data (second case))
         (first case)))
      (let ((cycle (list :request-id "cyclic-data" :command :list)))
        (setf (cdr (last cycle)) cycle)
        (invalid-result
         (make-instance 'hackmode-modules:module-catalog-request :data cycle)
         "Cyclic request property list"))))
  t)

(defun run-invalid-data-tests ()
  (let ((cycle (list "cycle")))
    (setf (cdr cycle) cycle)
    (expect-validation "Cyclic result metadata"
      (descriptor :result-schema cycle))
    (expect-validation "Cyclic enum choices"
      (option :mode :enum :choices cycle))
    (expect-validation "Cyclic option input"
      (instance-options (descriptor) cycle))
    (expect-validation "Cyclic catalog option input"
      (hackmode-modules:make-module-catalog-request
       :request-id "cyclic-options" :operation-id "operation-test"
       :command :instantiate :id "test/probe" :version "1.0" :options cycle)))
  (let ((cycle (cons nil "tail")))
    (setf (car cycle) cycle)
    (expect-validation "CAR-linked cyclic metadata"
      (descriptor :result-schema cycle)))
  (let ((closure (let ((value "local")) (lambda () value))))
    (expect-validation "Function-valued descriptor metadata"
      (descriptor :result-schema (list :callback closure)))
    (expect-validation "Function-valued option choices"
      (option :mode :enum :choices (list closure)))
    (expect-validation "Function-valued default"
      (option :value :string :default closure :default-present-p t))
    (expect-validation "Function-valued supplied option"
      (instance-options (descriptor :options (list (option :value :string)))
                        (list (cons :value closure)))))
  (let* ((shared (cons (copy-seq "shared") (copy-seq "tail")))
         (module (descriptor :result-schema (list shared shared))))
    (check-equal '(("shared" . "tail") ("shared" . "tail"))
                 (getf (hackmode-modules:module-info module) :result-schema)
                 "Shared acyclic local data must not be mistaken for a cycle"))
  (expect-validation "Missing operation identity"
    (hackmode-modules:instantiate-module (descriptor) nil))
  (expect-validation "Empty operation identity"
    (hackmode-modules:instantiate-module (descriptor) ""))
  t)

(defun run-public-invalid-input-tests ()
  (dolist (thunk (list
                 (lambda () (hackmode-modules:module-info 17))
                 (lambda () (hackmode-modules:module-option-info 17))
                 (lambda () (hackmode-modules:module-instance-info 17))
                 (lambda () (hackmode-modules:module-catalog-result-info 17))
                 (lambda () (hackmode-modules:find-module "test/probe" "1.0" :registry 17))
                 (lambda () (hackmode-modules:list-modules :registry 17))
                 (lambda () (hackmode-modules:list-module-families :registry 17))
                 (lambda () (hackmode-modules:register-module (descriptor) :registry 17))
                 (lambda () (hackmode-modules:unregister-module "test/probe" "1.0" :registry 17))
                 (lambda () (hackmode-modules:make-module-catalog-receiver :registry 17))
                 (lambda () (hackmode-modules:make-module-catalog-receiver :reply 17))
                 (lambda () (hackmode-modules:instantiate-module 17 "operation-test"))
                 (lambda () (hackmode-modules:module-payload-compatible-p 17 (descriptor :family :payload)))))
    (expect-validation "Invalid public object/registry argument" (funcall thunk)))
  (let ((info (hackmode-modules:module-catalog-result-info
               (hackmode-modules:handle-module-catalog-request
                (hackmode-modules:make-module-catalog-request
                 :request-id "bad-registry" :operation-id "operation-test" :command :list)
                :registry 17))))
    (check-equal :invalid-request (getf info :status) "Bad-registry protocol status")
    (check-equal "bad-registry" (getf info :request-id) "Bad-registry request correlation")
    (check-equal "operation-test" (getf info :operation-id) "Bad-registry operation correlation"))
  t)

(defun run-module-tests ()
  (run-descriptor-tests)
  (run-registry-tests)
  (run-metadata-string-tests)
  (run-option-tests)
  (run-copy-isolation-tests)
  (run-payload-compatibility-tests)
  (run-catalog-request-tests)
  (run-malformed-request-tests)
  (run-invalid-data-tests)
  (run-public-invalid-input-tests)
  t)
