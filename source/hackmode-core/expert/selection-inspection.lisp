(in-package :hackmode)

(defstruct (expert-objective-selection-inspection-state
             (:constructor %make-expert-objective-selection-inspection-state
                 (&key objective-id objective-version status raw-blockers
                       authority strategy selected-id selected-version reason
                       raw-candidates)))
  "Bounded operator-facing snapshot of objective evaluation and extension selection."
  (objective-id nil :read-only t)
  (objective-version nil :read-only t)
  (status nil :read-only t)
  (raw-blockers nil :read-only t)
  (authority nil :read-only t)
  (strategy nil :read-only t)
  (selected-id nil :read-only t)
  (selected-version nil :read-only t)
  (reason nil :read-only t)
  (raw-candidates nil :read-only t))

(defun copy-expert-inspection-string (value)
  (and value (copy-seq value)))

(defun copy-expert-inspection-blockers (blockers)
  (mapcar (lambda (blocker)
            (list (first blocker)
                  (copy-expert-inspection-string (second blocker))))
          blockers))

(defun copy-expert-inspection-candidates (candidates)
  (mapcar (lambda (candidate)
            (list (copy-expert-inspection-string (first candidate))
                  (copy-expert-inspection-string (second candidate))
                  (third candidate)))
          candidates))

(defun expert-objective-selection-inspection (evaluation selection)
  "Return bounded, side-effect-free objective and extension decision provenance.

Only clause kind/predicate identity is retained for unmet clauses. Clause
arguments are deliberately excluded so operator inspection cannot become a path
for secret-bearing objective data. Candidate records retain stable extension
identity/version plus the typed admission reason."
  (check-type evaluation expert-objective-evaluation)
  (check-type selection expert-extension-selection)
  (unless (and
           (string= (expert-objective-evaluation-objective-id evaluation)
                    (expert-extension-selection-objective-id selection))
           (string= (expert-objective-evaluation-objective-version evaluation)
                    (expert-extension-selection-objective-version selection)))
    (error "Objective evaluation and extension selection identities do not match"))
  (%make-expert-objective-selection-inspection-state
   :objective-id
   (copy-expert-inspection-string
    (expert-objective-evaluation-objective-id evaluation))
   :objective-version
   (copy-expert-inspection-string
    (expert-objective-evaluation-objective-version evaluation))
   :status (expert-objective-evaluation-status evaluation)
   :raw-blockers
   (mapcar
    (lambda (clause)
      (list (expert-objective-clause-kind clause)
            (copy-expert-inspection-string
             (expert-objective-clause-predicate clause))))
    (expert-objective-evaluation-unsatisfied-clauses evaluation))
   :authority (expert-extension-selection-authority selection)
   :strategy (expert-extension-selection-strategy selection)
   :selected-id
   (copy-expert-inspection-string
    (expert-extension-selection-selected-id selection))
   :selected-version
   (copy-expert-inspection-string
    (expert-extension-selection-selected-version selection))
   :reason (expert-extension-selection-reason selection)
   :raw-candidates
   (mapcar
    (lambda (candidate)
      (list (copy-expert-inspection-string
             (expert-extension-candidate-id candidate))
            (copy-expert-inspection-string
             (expert-extension-candidate-version candidate))
            (expert-extension-candidate-reason candidate)))
    (expert-extension-selection-candidates selection))))

(defun expert-objective-selection-inspection-objective-id (inspection)
  (copy-expert-inspection-string
   (expert-objective-selection-inspection-state-objective-id inspection)))

(defun expert-objective-selection-inspection-objective-version (inspection)
  (copy-expert-inspection-string
   (expert-objective-selection-inspection-state-objective-version inspection)))

(defun expert-objective-selection-inspection-status (inspection)
  (expert-objective-selection-inspection-state-status inspection))

(defun expert-objective-selection-inspection-blockers (inspection)
  (copy-expert-inspection-blockers
   (expert-objective-selection-inspection-state-raw-blockers inspection)))

(defun expert-objective-selection-inspection-authority (inspection)
  (expert-objective-selection-inspection-state-authority inspection))

(defun expert-objective-selection-inspection-strategy (inspection)
  (expert-objective-selection-inspection-state-strategy inspection))

(defun expert-objective-selection-inspection-selected-id (inspection)
  (copy-expert-inspection-string
   (expert-objective-selection-inspection-state-selected-id inspection)))

(defun expert-objective-selection-inspection-selected-version (inspection)
  (copy-expert-inspection-string
   (expert-objective-selection-inspection-state-selected-version inspection)))

(defun expert-objective-selection-inspection-reason (inspection)
  (expert-objective-selection-inspection-state-reason inspection))

(defun expert-objective-selection-inspection-candidates (inspection)
  (copy-expert-inspection-candidates
   (expert-objective-selection-inspection-state-raw-candidates inspection)))

(export '(expert-objective-selection-inspection
          expert-objective-selection-inspection-objective-id
          expert-objective-selection-inspection-objective-version
          expert-objective-selection-inspection-status
          expert-objective-selection-inspection-blockers
          expert-objective-selection-inspection-authority
          expert-objective-selection-inspection-strategy
          expert-objective-selection-inspection-selected-id
          expert-objective-selection-inspection-selected-version
          expert-objective-selection-inspection-reason
          expert-objective-selection-inspection-candidates))
