(in-package :hackmode)

(defparameter +expert-extension-authorities+ '(:passive :active)
  "Closed minimum authority requirements declared by expert extensions.")

(define-condition invalid-expert-extension (error)
  ((reason :initarg :reason :reader invalid-expert-extension-reason)
   (value :initarg :value :reader invalid-expert-extension-value))
  (:report (lambda (condition stream)
             (format stream "Invalid Hackpert extension: ~a"
                     (invalid-expert-extension-reason condition)))))

(defun reject-expert-extension (value control &rest arguments)
  (error 'invalid-expert-extension
         :value value
         :reason (apply #'format nil control arguments)))

(defun normalize-expert-extension-strings (values label)
  (unless (listp values)
    (reject-expert-extension values "~a must be a list" label))
  (unless (every #'expert-action-string-p values)
    (reject-expert-extension values
                             "~a must contain non-empty strings"
                             label))
  (let ((sorted (sort (copy-list values) #'string<)))
    (loop for tail on sorted
          while (cdr tail)
          when (string= (first tail) (second tail))
            do (reject-expert-extension
                values "duplicate ~a entry ~s" label (first tail)))
    sorted))

(defun normalize-expert-extension-strategies (strategies)
  (unless (and (listp strategies) strategies)
    (reject-expert-extension strategies
                             "strategies must contain at least one strategy"))
  (unless (every (lambda (strategy)
                   (member strategy +expert-reasoning-strategies+))
                 strategies)
    (reject-expert-extension strategies "unsupported reasoning strategy"))
  (remove-duplicates (copy-list strategies)))

(defstruct (expert-extension
             (:constructor %make-expert-extension
                 (&key id version raw-objective-predicates
                       raw-required-capabilities authority raw-strategies)))
  (id nil :read-only t)
  (version nil :read-only t)
  (raw-objective-predicates nil :read-only t)
  (raw-required-capabilities nil :read-only t)
  (authority :passive :read-only t)
  (raw-strategies nil :read-only t))

(defun make-expert-extension (&key id version objective-predicates
                                   required-capabilities authority strategies)
  "Create one declarative expert extension descriptor.

The descriptor declares applicability only. It grants no effects, executes no
provider, and owns no private scheduler or persistence state. AUTHORITY is the
minimum engine authority required for selection."
  (unless (expert-action-string-p id)
    (reject-expert-extension id "extension ID must be a non-empty string"))
  (unless (expert-action-string-p version)
    (reject-expert-extension version
                             "extension version must be a non-empty string"))
  (unless (and (listp objective-predicates) objective-predicates)
    (reject-expert-extension objective-predicates
                             "objective predicates must not be empty"))
  (unless (member authority +expert-extension-authorities+)
    (reject-expert-extension authority
                             "unsupported authority requirement ~s"
                             authority))
  (%make-expert-extension
   :id id
   :version version
   :raw-objective-predicates
   (normalize-expert-extension-strings objective-predicates
                                       "objective predicates")
   :raw-required-capabilities
   (normalize-expert-extension-strings required-capabilities
                                       "required capabilities")
   :authority authority
   :raw-strategies (normalize-expert-extension-strategies strategies)))

(defun expert-extension-objective-predicates (extension)
  (check-type extension expert-extension)
  (copy-list (expert-extension-raw-objective-predicates extension)))

(defun expert-extension-required-capabilities (extension)
  (check-type extension expert-extension)
  (copy-list (expert-extension-raw-required-capabilities extension)))

(defun expert-extension-strategies (extension)
  (check-type extension expert-extension)
  (copy-list (expert-extension-raw-strategies extension)))

(defstruct (expert-extension-registry
             (:constructor %make-expert-extension-registry (&key raw-extensions)))
  (raw-extensions nil :read-only t))

(defun make-expert-extension-registry ()
  "Create an empty functional extension registry."
  (%make-expert-extension-registry :raw-extensions nil))

(defun list-expert-extensions (registry)
  "Return extensions in deterministic stable-ID order."
  (check-type registry expert-extension-registry)
  (copy-list (expert-extension-registry-raw-extensions registry)))

(defun register-expert-extension (registry extension)
  "Return a new registry containing EXTENSION; reject duplicate stable IDs."
  (check-type registry expert-extension-registry)
  (check-type extension expert-extension)
  (when (find (expert-extension-id extension)
              (expert-extension-registry-raw-extensions registry)
              :key #'expert-extension-id
              :test #'string=)
    (reject-expert-extension extension
                             "extension ID ~s is already registered"
                             (expert-extension-id extension)))
  (%make-expert-extension-registry
   :raw-extensions
   (sort (cons extension
               (copy-list (expert-extension-registry-raw-extensions registry)))
         #'string<
         :key #'expert-extension-id)))

(defun expert-objective-predicate-names (objective)
  (mapcar #'expert-objective-clause-predicate
          (expert-objective-clauses objective)))

(defun expert-extension-authority-compatible-p (extension authority)
  (and (member authority +expert-extension-authorities+)
       (or (eq :passive (expert-extension-authority extension))
           (eq :active authority))))

(defun expert-extension-capabilities-available-p
    (extension objective available-capabilities)
  (let ((required (expert-extension-required-capabilities extension))
        (granted (expert-objective-granted-capabilities objective)))
    (and (every (lambda (capability)
                  (member capability granted :test #'string=))
                required)
         (every (lambda (capability)
                  (member capability available-capabilities :test #'string=))
                required))))

(defun expert-extension-applicable-p
    (extension objective &key authority strategy available-capabilities)
  "Return true when EXTENSION is admissible for OBJECTIVE under current policy.

Selection requires an understood objective predicate, compatible authority,
explicit strategy support, and every required capability both granted by the
objective and currently available. This function performs no effects."
  (check-type extension expert-extension)
  (check-type objective expert-objective)
  (unless (member strategy +expert-reasoning-strategies+)
    (reject-expert-extension strategy "unsupported reasoning strategy ~s" strategy))
  (unless (member authority +expert-extension-authorities+)
    (reject-expert-extension authority "unsupported authority ~s" authority))
  (unless (listp available-capabilities)
    (reject-expert-extension available-capabilities
                             "available capabilities must be a list"))
  (unless (every #'expert-action-string-p available-capabilities)
    (reject-expert-extension available-capabilities
                             "available capabilities must be non-empty strings"))
  (and
   (some (lambda (predicate)
           (member predicate
                   (expert-objective-predicate-names objective)
                   :test #'string=))
         (expert-extension-objective-predicates extension))
   (expert-extension-authority-compatible-p extension authority)
   (member strategy (expert-extension-strategies extension))
   (expert-extension-capabilities-available-p
    extension objective available-capabilities)))

(defun applicable-expert-extensions
    (registry objective &key authority strategy available-capabilities)
  "Return deterministic extensions applicable to OBJECTIVE and current policy."
  (remove-if-not
   (lambda (extension)
     (expert-extension-applicable-p
      extension objective
      :authority authority
      :strategy strategy
      :available-capabilities available-capabilities))
   (list-expert-extensions registry)))

(export '(+expert-extension-authorities+
          invalid-expert-extension
          invalid-expert-extension-reason
          invalid-expert-extension-value
          expert-extension
          make-expert-extension
          expert-extension-id
          expert-extension-version
          expert-extension-objective-predicates
          expert-extension-required-capabilities
          expert-extension-authority
          expert-extension-strategies
          expert-extension-registry
          make-expert-extension-registry
          register-expert-extension
          list-expert-extensions
          expert-extension-applicable-p
          applicable-expert-extensions))
