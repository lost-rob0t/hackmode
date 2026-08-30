(in-package :hackmode)

(defparameter +expert-objective-clause-kinds+
  '(:goal :precondition :evidence :constraint :stop)
  "Closed structural clause kinds for one normalized expert objective.")

(define-condition invalid-expert-objective (error)
  ((reason :initarg :reason :reader invalid-expert-objective-reason)
   (value :initarg :value :reader invalid-expert-objective-value))
  (:report (lambda (condition stream)
             (format stream "Invalid Hackpert objective: ~a"
                     (invalid-expert-objective-reason condition)))))

(defun reject-expert-objective (value control &rest arguments)
  (error 'invalid-expert-objective
         :value value
         :reason (apply #'format nil control arguments)))

(defstruct (expert-objective-clause
             (:constructor %make-expert-objective-clause
                 (&key kind predicate raw-arguments)))
  (kind nil :read-only t)
  (predicate nil :read-only t)
  (raw-arguments nil :read-only t))

(defun make-expert-objective-clause (&key kind predicate arguments)
  "Create one immutable-by-interface objective clause from typed data.

PREDICATE is declarative identity only. ARGUMENTS are copied as data and are
never interpreted as executable Prolog source by this layer."
  (unless (member kind +expert-objective-clause-kinds+)
    (reject-expert-objective kind "unsupported clause kind ~s" kind))
  (unless (expert-action-string-p predicate)
    (reject-expert-objective predicate
                             "clause predicate must be a non-empty string"))
  (unless (listp arguments)
    (reject-expert-objective arguments "clause arguments must be a list"))
  (%make-expert-objective-clause
   :kind kind
   :predicate predicate
   :raw-arguments (copy-tree arguments)))

(defun expert-objective-clause-arguments (clause)
  "Return a defensive copy of CLAUSE arguments."
  (check-type clause expert-objective-clause)
  (copy-tree (expert-objective-clause-raw-arguments clause)))

(defstruct (expert-objective-limit
             (:constructor %make-expert-objective-limit (&key name maximum)))
  (name nil :read-only t)
  (maximum 0 :read-only t))

(defun make-expert-objective-limit (&key name maximum)
  "Create one named non-negative objective budget limit."
  (unless (expert-action-string-p name)
    (reject-expert-objective name "limit name must be a non-empty string"))
  (unless (and (integerp maximum) (not (minusp maximum)))
    (reject-expert-objective maximum
                             "limit maximum must be a non-negative integer"))
  (%make-expert-objective-limit :name name :maximum maximum))

(defstruct (expert-objective
             (:constructor %make-expert-objective
                 (&key id version raw-clauses raw-limits raw-granted-capabilities)))
  (id nil :read-only t)
  (version nil :read-only t)
  (raw-clauses nil :read-only t)
  (raw-limits nil :read-only t)
  (raw-granted-capabilities nil :read-only t))

(defun normalize-expert-objective-capabilities (capabilities)
  (unless (listp capabilities)
    (reject-expert-objective capabilities
                             "granted capabilities must be a list"))
  (unless (every #'expert-action-string-p capabilities)
    (reject-expert-objective capabilities
                             "granted capabilities must be non-empty strings"))
  (let ((sorted (sort (copy-list capabilities) #'string<)))
    (loop for left on sorted
          while (cdr left)
          when (string= (first left) (second left))
            do (reject-expert-objective
                capabilities
                "duplicate granted capability ~s"
                (first left)))
    sorted))

(defun validate-expert-objective-limits (limits)
  (unless (listp limits)
    (reject-expert-objective limits "limits must be a list"))
  (unless (every (lambda (limit) (typep limit 'expert-objective-limit)) limits)
    (reject-expert-objective limits
                             "limits must contain expert objective limits"))
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (limit limits)
      (let ((name (expert-objective-limit-name limit)))
        (when (gethash name seen)
          (reject-expert-objective limits "duplicate limit name ~s" name))
        (setf (gethash name seen) t))))
  limits)

(defun make-expert-objective (&key id version clauses limits granted-capabilities)
  "Create a normalized operation-independent objective/SPEC definition.

The objective defines success, prerequisites, evidence requirements, constraints,
stop clauses, budgets, and capability grants as declarative data. It grants no
execution authority and encodes no fixed recon or attack phase ordering."
  (unless (expert-action-string-p id)
    (reject-expert-objective id "objective ID must be a non-empty string"))
  (unless (expert-action-string-p version)
    (reject-expert-objective version
                             "objective version must be a non-empty string"))
  (unless (and (listp clauses) clauses)
    (reject-expert-objective clauses
                             "objective requires at least one clause"))
  (unless (every (lambda (clause) (typep clause 'expert-objective-clause))
                 clauses)
    (reject-expert-objective clauses
                             "objective clauses must be normalized clauses"))
  (validate-expert-objective-limits limits)
  (%make-expert-objective
   :id id
   :version version
   :raw-clauses (copy-list clauses)
   :raw-limits (copy-list limits)
   :raw-granted-capabilities
   (normalize-expert-objective-capabilities granted-capabilities)))

(defun expert-objective-clauses (objective)
  "Return a defensive copy of OBJECTIVE clauses."
  (check-type objective expert-objective)
  (copy-list (expert-objective-raw-clauses objective)))

(defun expert-objective-limits (objective)
  "Return a defensive copy of OBJECTIVE limits."
  (check-type objective expert-objective)
  (copy-list (expert-objective-raw-limits objective)))

(defun expert-objective-granted-capabilities (objective)
  "Return deterministically normalized capability grants for OBJECTIVE."
  (check-type objective expert-objective)
  (copy-list (expert-objective-raw-granted-capabilities objective)))

(export '(+expert-objective-clause-kinds+
          invalid-expert-objective
          invalid-expert-objective-reason
          invalid-expert-objective-value
          expert-objective-clause
          make-expert-objective-clause
          expert-objective-clause-kind
          expert-objective-clause-predicate
          expert-objective-clause-arguments
          expert-objective-limit
          make-expert-objective-limit
          expert-objective-limit-name
          expert-objective-limit-maximum
          expert-objective
          make-expert-objective
          expert-objective-id
          expert-objective-version
          expert-objective-clauses
          expert-objective-limits
          expert-objective-granted-capabilities))
