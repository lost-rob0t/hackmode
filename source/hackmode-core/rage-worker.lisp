(in-package :hackmode)

(defparameter +rage-worker-modes+ '(:passive :active)
  "Hackpert execution modes supported by the RAGE worker substrate.")

(defparameter +rage-cyber-task-kinds+
  '(:recon
    :passive-analysis
    :source-security-review
    :vulnerability-research
    :vulnerability-validation
    :cve-correlation
    :authentication-testing
    :authorization-testing
    :session-testing
    :fuzzing
    :protocol-testing
    :api-security-testing
    :sqli-testing
    :xss-testing
    :oob-testing
    :exploitability-analysis
    :foothold
    :privilege-escalation
    :finding
    :security-report
    :security-projection
    :security-handoff)
  "Closed first-slice vocabulary of work this worker class may accept.")

(defstruct (rage-work-item
             (:constructor make-rage-work-item
                 (&key kind
                       (scope :external)
                       (description "")
                       operation-authorized-p
                       source
                       target)))
  "A candidate unit of cyber work presented to a Hackmode RAGE worker.

SCOPE is an explicit authority label supplied by the caller.  In particular,
:STARINTEL means the item touches StarIntel as a target, security corpus, or
security integration surface; it does not mean the worker may perform ordinary
StarIntel product engineering."
  (kind :recon :type keyword)
  (scope :external :type keyword)
  (description "" :type string)
  (operation-authorized-p nil :type boolean)
  source
  target)

(defstruct (rage-scope-decision
             (:constructor %make-rage-scope-decision))
  "Pure authorization decision for a RAGE work item."
  (allowed-p nil :type boolean)
  (reason :denied :type keyword)
  work-item)

(defstruct (rage-worker
             (:constructor %make-rage-worker))
  "Identity and run-local state for one Hackmode RAGE worker."
  (id "" :type string)
  (run-id "" :type string)
  operation
  (mode :passive :type keyword)
  objective
  (state :idle :type keyword))

(defun non-empty-string-p (value)
  (and (stringp value) (plusp (length value))))

(defun make-rage-worker (&key id run-id operation (mode :passive) objective)
  "Create one isolated RAGE worker identity.

The first worker substrate deliberately accepts only Hackpert's PASSIVE and
ACTIVE modes.  Future RLM/LLM escalation is an extension inside the worker loop,
not a third authority-bearing worker mode unless that contract is explicitly
added later."
  (unless (non-empty-string-p id)
    (error "RAGE worker ID must be a non-empty string."))
  (unless (non-empty-string-p run-id)
    (error "RAGE worker run ID must be a non-empty string."))
  (unless (member mode +rage-worker-modes+)
    (error "Unsupported RAGE worker mode ~s; expected one of ~s."
           mode +rage-worker-modes+))
  (%make-rage-worker :id id
                     :run-id run-id
                     :operation operation
                     :mode mode
                     :objective objective
                     :state :idle))

(defun rage-cyber-task-kind-p (kind)
  "Return true when KIND belongs to the closed RAGE cyber work vocabulary."
  (not (null (member kind +rage-cyber-task-kinds+))))

(defun starintel-rage-scope-p (work-item)
  "Return true when WORK-ITEM explicitly targets the StarIntel security scope."
  (eq :starintel (rage-work-item-scope work-item)))

(defun authorize-rage-work-item (work-item)
  "Return a RAGE-SCOPE-DECISION for WORK-ITEM without causing side effects.

All RAGE workers are cyber workers.  StarIntel receives an additional explicit
guardrail: a StarIntel-scoped item that is not in the cyber vocabulary is
rejected with :STARINTEL-CYBER-ONLY, making it impossible for the migrated
worker to silently fall back into StarIntel product issue implementation."
  (check-type work-item rage-work-item)
  (cond
    ((not (rage-work-item-operation-authorized-p work-item))
     (%make-rage-scope-decision
      :allowed-p nil
      :reason :operation-not-authorized
      :work-item work-item))
    ((and (starintel-rage-scope-p work-item)
          (not (rage-cyber-task-kind-p (rage-work-item-kind work-item))))
     (%make-rage-scope-decision
      :allowed-p nil
      :reason :starintel-cyber-only
      :work-item work-item))
    ((not (rage-cyber-task-kind-p (rage-work-item-kind work-item)))
     (%make-rage-scope-decision
      :allowed-p nil
      :reason :non-cyber-work
      :work-item work-item))
    (t
     (%make-rage-scope-decision
      :allowed-p t
      :reason :authorized
      :work-item work-item))))

(defun rage-worker-can-accept-p (worker work-item)
  "Return two values: whether WORKER may accept WORK-ITEM and its decision.

This first slice does not dispatch providers or mutate canonical state.  It
only establishes the worker identity/scope gate that later active orchestration
must call before execution."
  (check-type worker rage-worker)
  (let ((decision (authorize-rage-work-item work-item)))
    (values (rage-scope-decision-allowed-p decision) decision)))

(export '(+rage-worker-modes+
          +rage-cyber-task-kinds+
          rage-work-item
          make-rage-work-item
          rage-work-item-kind
          rage-work-item-scope
          rage-work-item-description
          rage-work-item-operation-authorized-p
          rage-work-item-source
          rage-work-item-target
          rage-scope-decision
          rage-scope-decision-allowed-p
          rage-scope-decision-reason
          rage-scope-decision-work-item
          rage-worker
          make-rage-worker
          rage-worker-id
          rage-worker-run-id
          rage-worker-operation
          rage-worker-mode
          rage-worker-objective
          rage-worker-state
          rage-cyber-task-kind-p
          starintel-rage-scope-p
          authorize-rage-work-item
          rage-worker-can-accept-p))
