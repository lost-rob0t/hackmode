(in-package :hackmode)

(defparameter +expert-direct-candidate-kinds+ '(:rule :plan :evidence :kb)
  "Typed outputs that direct reasoning may return to symbolic execution.")

(define-condition invalid-expert-direct-candidate (error)
  ((reason :initarg :reason :reader invalid-expert-direct-candidate-reason)
   (value :initarg :value :reader invalid-expert-direct-candidate-value))
  (:report (lambda (condition stream)
             (format stream "Invalid direct reasoning candidate: ~a"
                     (invalid-expert-direct-candidate-reason condition)))))

(defun reject-expert-direct-candidate (value control &rest arguments)
  (error 'invalid-expert-direct-candidate
         :value value
         :reason (apply #'format nil control arguments)))

(defun expert-direct-copy-value (value)
  (typecase value
    (string (copy-seq value))
    (cons (cons (expert-direct-copy-value (car value))
                (expert-direct-copy-value (cdr value))))
    (vector (map 'vector #'expert-direct-copy-value value))
    (t value)))

(defstruct (expert-direct-candidate
             (:constructor %make-expert-direct-candidate
                 (&key operation run-id kind payload provenance))
             (:conc-name %expert-direct-candidate-))
  operation
  run-id
  kind
  payload
  provenance)

(defun expert-direct-candidate-operation (candidate)
  "Return an independently mutable snapshot of CANDIDATE's operation scope."
  (check-type candidate expert-direct-candidate)
  (copy-seq (%expert-direct-candidate-operation candidate)))

(defun expert-direct-candidate-run-id (candidate)
  "Return an independently mutable snapshot of CANDIDATE's run scope."
  (check-type candidate expert-direct-candidate)
  (copy-seq (%expert-direct-candidate-run-id candidate)))

(defun expert-direct-candidate-kind (candidate)
  "Return CANDIDATE's immutable typed kind."
  (check-type candidate expert-direct-candidate)
  (%expert-direct-candidate-kind candidate))

(defun expert-direct-candidate-payload (candidate)
  "Return a defensive snapshot of CANDIDATE's symbolic payload."
  (check-type candidate expert-direct-candidate)
  (expert-direct-copy-value (%expert-direct-candidate-payload candidate)))

(defun expert-direct-candidate-provenance (candidate)
  "Return a defensive snapshot of CANDIDATE's generation provenance."
  (check-type candidate expert-direct-candidate)
  (expert-direct-copy-value (%expert-direct-candidate-provenance candidate)))

(defun make-expert-direct-candidate (&key operation run-id kind payload provenance)
  "Normalize direct-mode progress into a typed, operation-scoped candidate.

Candidates are data only. They grant no provider or mutation authority and are
returned to symbolic execution for validation/acceptance by the existing
Hackmode boundaries."
  (unless (expert-action-string-p operation)
    (reject-expert-direct-candidate operation
                                    "operation must be a non-empty string"))
  (unless (expert-action-string-p run-id)
    (reject-expert-direct-candidate run-id
                                    "run ID must be a non-empty string"))
  (unless (member kind +expert-direct-candidate-kinds+)
    (reject-expert-direct-candidate kind
                                    "unsupported candidate kind ~s" kind))
  (when (null payload)
    (reject-expert-direct-candidate payload "payload must not be NIL"))
  (%make-expert-direct-candidate
   :operation (copy-seq operation)
   :run-id (copy-seq run-id)
   :kind kind
   :payload (expert-direct-copy-value payload)
   :provenance (expert-direct-copy-value provenance)))

(defun validate-expert-direct-candidate-scope (state candidate)
  (unless (string= (expert-loop-state-operation state)
                   (%expert-direct-candidate-operation candidate))
    (reject-expert-direct-candidate
     candidate
     "candidate operation ~s does not match loop operation ~s"
     (%expert-direct-candidate-operation candidate)
     (expert-loop-state-operation state)))
  (unless (string= (expert-loop-state-run-id state)
                   (%expert-direct-candidate-run-id candidate))
    (reject-expert-direct-candidate
     candidate
     "candidate run ~s does not match loop run ~s"
     (%expert-direct-candidate-run-id candidate)
     (expert-loop-state-run-id state)))
  candidate)

(defun expert-loop-resume-with-direct-candidate (state plan policy candidate)
  "Resume symbolic reasoning only after direct progress has a typed candidate.

This is a pure normalization/transition boundary. It neither executes the
candidate nor persists it. Authority remains entirely orthogonal to reasoning
strategy."
  (check-type state expert-loop-state)
  (check-type plan expert-plan)
  (check-type policy expert-loop-policy)
  (check-type candidate expert-direct-candidate)
  (unless (eq :direct (expert-loop-state-strategy state))
    (reject-expert-direct-candidate
     state "loop strategy must be DIRECT before candidate normalization"))
  (validate-expert-loop-scope state plan)
  (validate-expert-direct-candidate-scope state candidate)
  (multiple-value-bind (decision next-state)
      (expert-loop-next-decision state plan policy :progress-p t :failure-p nil)
    (unless (eq :resume-symbolic (expert-loop-decision-kind decision))
      (reject-expert-direct-candidate
       decision "direct progress did not produce a symbolic resume decision"))
    (values decision next-state candidate)))

(export '(+expert-direct-candidate-kinds+
          invalid-expert-direct-candidate
          invalid-expert-direct-candidate-reason
          invalid-expert-direct-candidate-value
          expert-direct-candidate
          make-expert-direct-candidate
          expert-direct-candidate-operation
          expert-direct-candidate-run-id
          expert-direct-candidate-kind
          expert-direct-candidate-payload
          expert-direct-candidate-provenance
          expert-loop-resume-with-direct-candidate))
