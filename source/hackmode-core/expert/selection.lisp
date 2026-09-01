(in-package :hackmode)

(defparameter +expert-objective-evaluation-statuses+
  '(:blocked :in-progress :satisfied)
  "Closed statuses produced when an objective is re-evaluated against evidence.")

(defparameter +expert-extension-candidate-reasons+
  '(:applicable
    :objective-predicate-mismatch
    :authority-denied
    :strategy-unsupported
    :capability-not-granted
    :capability-unavailable)
  "Closed explanations for extension candidate admission decisions.")

(defun expert-selection-copy-identity (value)
  (if (stringp value)
      (copy-seq value)
      value))

(defstruct (expert-objective-evaluation
             (:constructor %make-expert-objective-evaluation
                 (&key objective-id objective-version status raw-unsatisfied-clauses))
             (:conc-name %expert-objective-evaluation-))
  (objective-id nil :read-only t)
  (objective-version nil :read-only t)
  (status :in-progress :read-only t)
  (raw-unsatisfied-clauses nil :read-only t))

(defun expert-objective-evaluation-objective-id (evaluation)
  (check-type evaluation expert-objective-evaluation)
  (expert-selection-copy-identity
   (%expert-objective-evaluation-objective-id evaluation)))

(defun expert-objective-evaluation-objective-version (evaluation)
  (check-type evaluation expert-objective-evaluation)
  (expert-selection-copy-identity
   (%expert-objective-evaluation-objective-version evaluation)))

(defun expert-objective-evaluation-status (evaluation)
  (check-type evaluation expert-objective-evaluation)
  (%expert-objective-evaluation-status evaluation))

(defun expert-objective-evaluation-unsatisfied-clauses (evaluation)
  "Return deterministic unmet objective clauses as a defensive list copy."
  (check-type evaluation expert-objective-evaluation)
  (copy-list (%expert-objective-evaluation-raw-unsatisfied-clauses evaluation)))

(defun expert-objective-runtime-clause-p (clause)
  (member (expert-objective-clause-kind clause)
          '(:goal :precondition :evidence :constraint)))

(defun evaluate-expert-objective (objective clause-satisfied-p)
  "Re-evaluate OBJECTIVE using CLAUSE-SATISFIED-P over declarative clauses.

The callback receives normalized clause data and must return generalized truth.
Stop clauses are policy declarations rather than evidence assertions, so they do
not participate in satisfaction. This function performs no effects and owns no
canonical state."
  (check-type objective expert-objective)
  (check-type clause-satisfied-p function)
  (let* ((runtime-clauses
           (remove-if-not #'expert-objective-runtime-clause-p
                          (expert-objective-clauses objective)))
         (unsatisfied
           (sort
            (remove-if clause-satisfied-p (copy-list runtime-clauses))
            #'string<
            :key #'expert-objective-clause-predicate))
         (blocked-p
           (some (lambda (clause)
                   (member (expert-objective-clause-kind clause)
                           '(:precondition :constraint)))
                 unsatisfied))
         (goal-or-evidence-unmet-p
           (some (lambda (clause)
                   (member (expert-objective-clause-kind clause)
                           '(:goal :evidence)))
                 unsatisfied))
         (status
           (cond
             (blocked-p :blocked)
             (goal-or-evidence-unmet-p :in-progress)
             (t :satisfied))))
    (%make-expert-objective-evaluation
     :objective-id (expert-objective-id objective)
     :objective-version (expert-objective-version objective)
     :status status
     :raw-unsatisfied-clauses unsatisfied)))

(defstruct (expert-extension-candidate
             (:constructor make-expert-extension-candidate
                 (&key id version reason))
             (:conc-name %expert-extension-candidate-))
  (id nil :read-only t)
  (version nil :read-only t)
  (reason nil :read-only t))

(defun expert-extension-candidate-id (candidate)
  (check-type candidate expert-extension-candidate)
  (expert-selection-copy-identity (%expert-extension-candidate-id candidate)))

(defun expert-extension-candidate-version (candidate)
  (check-type candidate expert-extension-candidate)
  (expert-selection-copy-identity (%expert-extension-candidate-version candidate)))

(defun expert-extension-candidate-reason (candidate)
  (check-type candidate expert-extension-candidate)
  (%expert-extension-candidate-reason candidate))

(defstruct (expert-extension-selection
             (:constructor %make-expert-extension-selection
                 (&key objective-id objective-version authority strategy
                       selected-id selected-version reason raw-candidates))
             (:conc-name %expert-extension-selection-))
  (objective-id nil :read-only t)
  (objective-version nil :read-only t)
  (authority nil :read-only t)
  (strategy nil :read-only t)
  (selected-id nil :read-only t)
  (selected-version nil :read-only t)
  (reason nil :read-only t)
  (raw-candidates nil :read-only t))

(defun expert-extension-selection-objective-id (selection)
  (check-type selection expert-extension-selection)
  (expert-selection-copy-identity
   (%expert-extension-selection-objective-id selection)))

(defun expert-extension-selection-objective-version (selection)
  (check-type selection expert-extension-selection)
  (expert-selection-copy-identity
   (%expert-extension-selection-objective-version selection)))

(defun expert-extension-selection-authority (selection)
  (check-type selection expert-extension-selection)
  (%expert-extension-selection-authority selection))

(defun expert-extension-selection-strategy (selection)
  (check-type selection expert-extension-selection)
  (%expert-extension-selection-strategy selection))

(defun expert-extension-selection-selected-id (selection)
  (check-type selection expert-extension-selection)
  (expert-selection-copy-identity
   (%expert-extension-selection-selected-id selection)))

(defun expert-extension-selection-selected-version (selection)
  (check-type selection expert-extension-selection)
  (expert-selection-copy-identity
   (%expert-extension-selection-selected-version selection)))

(defun expert-extension-selection-reason (selection)
  (check-type selection expert-extension-selection)
  (%expert-extension-selection-reason selection))

(defun expert-extension-selection-candidates (selection)
  "Return candidate decision provenance as a defensive list copy."
  (check-type selection expert-extension-selection)
  (copy-list (%expert-extension-selection-raw-candidates selection)))

(defun expert-extension-understands-objective-p (extension objective)
  (some (lambda (predicate)
          (member predicate
                  (expert-objective-predicate-names objective)
                  :test #'string=))
        (expert-extension-objective-predicates extension)))

(defun first-missing-expert-capability (required available)
  (find-if-not (lambda (capability)
                 (member capability available :test #'string=))
               required))

(defun expert-extension-admission-reason
    (extension objective &key authority strategy available-capabilities)
  "Return the first deterministic reason EXTENSION is accepted or rejected."
  (check-type extension expert-extension)
  (check-type objective expert-objective)
  (unless (member authority +expert-extension-authorities+)
    (reject-expert-extension authority "unsupported authority ~s" authority))
  (unless (member strategy +expert-reasoning-strategies+)
    (reject-expert-extension strategy "unsupported reasoning strategy ~s" strategy))
  (unless (and (listp available-capabilities)
               (every #'expert-action-string-p available-capabilities))
    (reject-expert-extension available-capabilities
                             "available capabilities must be non-empty strings"))
  (let* ((required (expert-extension-required-capabilities extension))
         (granted (expert-objective-granted-capabilities objective)))
    (cond
      ((not (expert-extension-understands-objective-p extension objective))
       :objective-predicate-mismatch)
      ((not (expert-extension-authority-compatible-p extension authority))
       :authority-denied)
      ((not (member strategy (expert-extension-strategies extension)))
       :strategy-unsupported)
      ((first-missing-expert-capability required granted)
       :capability-not-granted)
      ((first-missing-expert-capability required available-capabilities)
       :capability-unavailable)
      (t :applicable))))

(defun expert-select-extension
    (registry objective &key authority strategy available-capabilities
                          clause-satisfied-p)
  "Re-evaluate OBJECTIVE and deterministically select one applicable extension.

Returns two values: an objective evaluation and an explainable selection record.
A satisfied objective selects no extension. Otherwise the first applicable
extension in stable registry order is selected; every considered extension keeps
an explicit admission/rejection reason. No provider or mutation effect occurs."
  (check-type registry expert-extension-registry)
  (check-type objective expert-objective)
  (let* ((evaluation (evaluate-expert-objective objective clause-satisfied-p))
         (extensions (list-expert-extensions registry))
         (candidates
           (mapcar
            (lambda (extension)
              (make-expert-extension-candidate
               :id (expert-extension-id extension)
               :version (expert-extension-version extension)
               :reason
               (expert-extension-admission-reason
                extension objective
                :authority authority
                :strategy strategy
                :available-capabilities available-capabilities)))
            extensions)))
    (if (eq :satisfied (expert-objective-evaluation-status evaluation))
        (values
         evaluation
         (%make-expert-extension-selection
          :objective-id (expert-objective-id objective)
          :objective-version (expert-objective-version objective)
          :authority authority
          :strategy strategy
          :selected-id nil
          :selected-version nil
          :reason :objective-satisfied
          :raw-candidates candidates))
        (let ((selected
                (find :applicable candidates
                      :key #'expert-extension-candidate-reason)))
          (values
           evaluation
           (%make-expert-extension-selection
            :objective-id (expert-objective-id objective)
            :objective-version (expert-objective-version objective)
            :authority authority
            :strategy strategy
            :selected-id (and selected (expert-extension-candidate-id selected))
            :selected-version
            (and selected (expert-extension-candidate-version selected))
            :reason (if selected :selected :no-applicable-extension)
            :raw-candidates candidates))))))

(defun expert-objective-loop-step
    (state plan policy registry objective
     &key authority available-capabilities clause-satisfied-p
       progress-p failure-p budget-exhausted-p policy-denied-p explicit-stop-p)
  "Re-evaluate one objective iteration before deriving the next loop decision.

Returns four values: the fresh objective evaluation, extension selection, loop
decision, and next loop state. The current loop reasoning strategy is used for
extension admission, while AUTHORITY remains an independent caller-supplied
constraint. This function is pure control-plane composition: it executes no
provider, persists no state, and grants no effects."
  (check-type state expert-loop-state)
  (check-type plan expert-plan)
  (check-type policy expert-loop-policy)
  (check-type registry expert-extension-registry)
  (check-type objective expert-objective)
  (unless (string= (expert-plan-objective-id plan)
                   (expert-objective-id objective))
    (reject-expert-loop
     objective
     "plan objective ~s does not match objective ~s"
     (expert-plan-objective-id plan)
     (expert-objective-id objective)))
  (multiple-value-bind (evaluation selection)
      (expert-select-extension
       registry objective
       :authority authority
       :strategy (expert-loop-state-strategy state)
       :available-capabilities available-capabilities
       :clause-satisfied-p clause-satisfied-p)
    (multiple-value-bind (decision next-state)
        (expert-loop-next-decision
         state plan policy
         :goal-satisfied-p
         (eq :satisfied (expert-objective-evaluation-status evaluation))
         :budget-exhausted-p budget-exhausted-p
         :policy-denied-p policy-denied-p
         :viable-extension-p
         (not (null (expert-extension-selection-selected-id selection)))
         :explicit-stop-p explicit-stop-p
         :progress-p progress-p
         :failure-p failure-p)
      (values evaluation selection decision next-state))))

(export '(+expert-objective-evaluation-statuses+
          +expert-extension-candidate-reasons+
          expert-objective-evaluation
          expert-objective-evaluation-objective-id
          expert-objective-evaluation-objective-version
          expert-objective-evaluation-status
          expert-objective-evaluation-unsatisfied-clauses
          evaluate-expert-objective
          expert-extension-candidate
          expert-extension-candidate-id
          expert-extension-candidate-version
          expert-extension-candidate-reason
          expert-extension-admission-reason
          expert-extension-selection
          expert-extension-selection-objective-id
          expert-extension-selection-objective-version
          expert-extension-selection-authority
          expert-extension-selection-strategy
          expert-extension-selection-selected-id
          expert-extension-selection-selected-version
          expert-extension-selection-reason
          expert-extension-selection-candidates
          expert-select-extension
          expert-objective-loop-step))
