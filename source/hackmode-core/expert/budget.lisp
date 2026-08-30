(in-package :hackmode)

(define-condition invalid-expert-budget (error)
  ((reason :initarg :reason :reader invalid-expert-budget-reason)
   (value :initarg :value :reader invalid-expert-budget-value))
  (:report (lambda (condition stream)
             (format stream "Invalid Hackpert budget state: ~a"
                     (invalid-expert-budget-reason condition)))))

(define-condition expert-budget-denied (error)
  ((name :initarg :name :reader expert-budget-denied-name)
   (requested :initarg :requested :reader expert-budget-denied-requested)
   (remaining :initarg :remaining :reader expert-budget-denied-remaining))
  (:report (lambda (condition stream)
             (format stream "Hackpert budget ~s denies ~d unit~:p; ~d remain."
                     (expert-budget-denied-name condition)
                     (expert-budget-denied-requested condition)
                     (expert-budget-denied-remaining condition)))))

(defun reject-expert-budget (value control &rest arguments)
  (error 'invalid-expert-budget
         :value value
         :reason (apply #'format nil control arguments)))

(defstruct (expert-budget-state
             (:constructor %make-expert-budget-state
                 (&key objective-id objective-version operation run-id raw-limits raw-used)))
  (objective-id nil :read-only t)
  (objective-version nil :read-only t)
  (operation nil :read-only t)
  (run-id nil :read-only t)
  (raw-limits nil :read-only t)
  (raw-used nil :read-only t))

(defun make-expert-budget-state (objective &key operation run-id)
  "Create immutable run-scoped budget state from OBJECTIVE limits.

Budget accounting is an admission input only. It grants no authority and owns no
persistence; callers may persist accepted state through canonical Hackmode APIs."
  (check-type objective expert-objective)
  (unless (expert-action-string-p operation)
    (reject-expert-budget operation "operation must be a non-empty string"))
  (unless (expert-action-string-p run-id)
    (reject-expert-budget run-id "run ID must be a non-empty string"))
  (%make-expert-budget-state
   :objective-id (expert-objective-id objective)
   :objective-version (expert-objective-version objective)
   :operation operation
   :run-id run-id
   :raw-limits
   (mapcar (lambda (limit)
             (cons (expert-objective-limit-name limit)
                   (expert-objective-limit-maximum limit)))
           (expert-objective-limits objective))
   :raw-used nil))

(defun expert-budget-limit (state name)
  (check-type state expert-budget-state)
  (unless (expert-action-string-p name)
    (reject-expert-budget name "budget name must be a non-empty string"))
  (or (assoc name (expert-budget-state-raw-limits state) :test #'string=)
      (reject-expert-budget name "unknown objective budget ~s" name)))

(defun expert-budget-used (state name)
  (or (cdr (assoc name (expert-budget-state-raw-used state) :test #'string=)) 0))

(defun expert-budget-remaining (state name)
  "Return remaining units for NAME in STATE."
  (let ((limit (expert-budget-limit state name)))
    (- (cdr limit) (expert-budget-used state name))))

(defun expert-budget-exhausted-p (state &optional name)
  "Return true when NAME, or any declared budget when NAME is NIL, is exhausted."
  (check-type state expert-budget-state)
  (if name
      (zerop (expert-budget-remaining state name))
      (some (lambda (limit)
              (zerop (expert-budget-remaining state (car limit))))
            (expert-budget-state-raw-limits state))))

(defun expert-budget-consume (state name &key (amount 1))
  "Return a new STATE with AMOUNT consumed from NAME, failing closed on overflow."
  (check-type state expert-budget-state)
  (unless (and (integerp amount) (plusp amount))
    (reject-expert-budget amount "consume amount must be a positive integer"))
  (let ((remaining (expert-budget-remaining state name)))
    (when (> amount remaining)
      (error 'expert-budget-denied
             :name name :requested amount :remaining remaining))
    (let* ((used (expert-budget-used state name))
           (new-used (acons name (+ used amount)
                            (remove name
                                    (expert-budget-state-raw-used state)
                                    :key #'car :test #'string=))))
      (%make-expert-budget-state
       :objective-id (expert-budget-state-objective-id state)
       :objective-version (expert-budget-state-objective-version state)
       :operation (expert-budget-state-operation state)
       :run-id (expert-budget-state-run-id state)
       :raw-limits (copy-tree (expert-budget-state-raw-limits state))
       :raw-used new-used))))

(export '(invalid-expert-budget
          invalid-expert-budget-reason
          invalid-expert-budget-value
          expert-budget-denied
          expert-budget-denied-name
          expert-budget-denied-requested
          expert-budget-denied-remaining
          expert-budget-state
          make-expert-budget-state
          expert-budget-state-objective-id
          expert-budget-state-objective-version
          expert-budget-state-operation
          expert-budget-state-run-id
          expert-budget-remaining
          expert-budget-exhausted-p
          expert-budget-consume))
