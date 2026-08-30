(in-package :hackmode)

(defparameter *expert-program* "swipl"
  "SWI-Prolog executable used by the optional Hackmode expert layer.")

(defparameter +expert-engine-modes+ '(:passive :active)
  "Closed authority-mode vocabulary for the Hackpert expert engine.")

(defparameter +expert-effect-kinds+
  '(:reasoning :provider-dispatch :canonical-mutation)
  "First-slice effect classes admitted by the Hackpert authority gate.")

(define-condition expert-unavailable (error)
  ((program :initarg :program :reader expert-unavailable-program))
  (:report (lambda (condition stream)
             (format stream "Hackmode expert layer is unavailable: ~a was not found or could not run."
                     (expert-unavailable-program condition)))))

(define-condition expert-query-failed (error)
  ((status :initarg :status :reader expert-query-failed-status)
   (stderr :initarg :stderr :reader expert-query-failed-stderr))
  (:report (lambda (condition stream)
             (format stream "Hackmode expert query failed with status ~a~@[: ~a~]"
                     (expert-query-failed-status condition)
                     (let ((stderr (expert-query-failed-stderr condition)))
                       (and stderr
                            (plusp (length stderr))
                            stderr))))))

(define-condition invalid-expert-engine-mode (error)
  ((mode :initarg :mode :reader invalid-expert-engine-mode-value))
  (:report (lambda (condition stream)
             (format stream "Unsupported Hackpert engine mode ~s; expected one of ~s."
                     (invalid-expert-engine-mode-value condition)
                     +expert-engine-modes+))))

(define-condition expert-effect-denied (error)
  ((engine :initarg :engine :reader expert-effect-denied-engine)
   (effect :initarg :effect :reader expert-effect-denied-effect))
  (:report (lambda (condition stream)
             (format stream "Hackpert ~s mode denies effect ~s."
                     (expert-engine-mode (expert-effect-denied-engine condition))
                     (expert-effect-denied-effect condition)))))

(defstruct (expert-engine
             (:constructor %make-expert-engine (mode)))
  "Hackpert reasoning engine with explicit execution authority.

MODE controls effect authority only. Reasoning strategy (direct, symbolic,
expert rules, or later RLM escalation) is an orthogonal concern and must not
silently widen this authority."
  (mode :passive :type keyword))

(defun make-expert-engine (&key (mode :passive))
  "Create a Hackpert engine in explicit PASSIVE or ACTIVE authority mode.

PASSIVE is the default so constructing an engine never accidentally grants
provider-dispatch or canonical-mutation authority."
  (unless (member mode +expert-engine-modes+)
    (error 'invalid-expert-engine-mode :mode mode))
  (%make-expert-engine mode))

(defun expert-engine-effect-authorized-p (engine effect)
  "Return true when ENGINE may request EFFECT under its authority mode.

This is a pure gate. It does not execute providers or mutate state. Unknown
effect classes fail closed. PASSIVE may reason only; ACTIVE may additionally
request provider dispatch and canonical mutation through later typed action
validation and Hackmode's canonical effect boundaries."
  (check-type engine expert-engine)
  (and (member effect +expert-effect-kinds+)
       (or (eq effect :reasoning)
           (eq (expert-engine-mode engine) :active))))

(defun require-expert-engine-effect (engine effect)
  "Return EFFECT when authorized, otherwise signal EXPERT-EFFECT-DENIED.

Call this at effect admission boundaries before any provider dispatch or
canonical mutation. It is deliberately not an executor itself."
  (unless (expert-engine-effect-authorized-p engine effect)
    (error 'expert-effect-denied :engine engine :effect effect))
  effect)

(defstruct expert-recommendation
  capability
  provider
  priority)

(defun expert-available-p (&optional (program *expert-program*))
  "Return true when PROGRAM can execute as SWI-Prolog.

Hackmode does not require Prolog for normal operation; this probe is intentionally
isolated from startup and canonical state initialization."
  (handler-case
      (progn
        (uiop:run-program (list program "--version")
                          :output nil
                          :error-output nil)
        t)
    (error () nil)))

(defun expert-rules-path ()
  (asdf:system-relative-pathname :hackmode "expert/hackmode_expert.pl"))

(defun prolog-write-string (stream value)
  "Write VALUE as an escaped SWI-Prolog string literal."
  (write-char #\" stream)
  (loop for character across (or value "")
        for code = (char-code character)
        do (case character
             (#\\ (write-string "\\\\" stream))
             (#\" (write-string "\\\"" stream))
             (#\Newline (write-string "\\n" stream))
             (#\Return (write-string "\\r" stream))
             (#\Tab (write-string "\\t" stream))
             (otherwise
              (if (or (< code 32) (= code 127))
                  (format stream "\\x~x\\" code)
                  (write-char character stream)))))
  (write-char #\" stream))

(defun prolog-write-value (stream value)
  (etypecase value
    (integer (princ value stream))
    (string (prolog-write-string stream value))))

(defun write-expert-fact (stream predicate &rest values)
  (format stream "~a(" predicate)
  (loop for value in values
        for first = t then nil
        do (unless first (write-char #\, stream))
           (prolog-write-value stream value))
  (write-string ")." stream)
  (terpri stream))

(defun expert-current-assets ()
  (if (and *db* (tek9:db-is-open-p *db*))
      (query-assets :database *db*)
      nil))

(defun expert-type-name (value)
  (let* ((raw (cond
                ((null value) "any")
                ((symbolp value) (symbol-name value))
                (t (princ-to-string value))))
         (name (string-downcase raw))
         (colon (position #\: name :from-end t)))
    (when colon
      (setf name (subseq name (1+ colon))))
    (cond
      ((member name '("meta" "t") :test #'string=) "any")
      ((string= name "cert") "certificate")
      (t name))))

(defun expert-asset-value (asset)
  (or (ignore-errors (asset-canonical-value asset))
      (doc-id asset)
      ""))

(defun expert-provider< (left right)
  (let ((left-priority (capability-provider-priority left))
        (right-priority (capability-provider-priority right)))
    (or (< left-priority right-priority)
        (and (= left-priority right-priority)
             (string<
              (format nil "~a/~a"
                      (capability-provider-capability left)
                      (capability-provider-name left))
              (format nil "~a/~a"
                      (capability-provider-capability right)
                      (capability-provider-name right)))))))

(defun expert-snapshot (&key
                          (operation (current-operation))
                          (assets (expert-current-assets))
                          (providers (list-capability-providers))
                          query-target
                          query-asset)
  "Return a deterministic Prolog fact snapshot of canonical Hackmode state.

The snapshot is derived data only. It never becomes operation authority and is
safe to discard after a query. QUERY-TARGET and QUERY-ASSET are internal query
inputs serialized as data facts so caller-controlled text never becomes a Prolog
goal."
  (with-output-to-string (stream)
    (when operation
      (write-expert-fact stream "operation" (operation-name operation)))
    (dolist (asset
             (sort (copy-list assets) #'string<
                   :key (lambda (item) (or (doc-id item) ""))))
      (write-expert-fact stream
                         "asset"
                         (or (doc-id asset) "")
                         (asset-kind asset)
                         (expert-asset-value asset)))
    (dolist (provider
             (sort (copy-list providers) #'expert-provider<))
      (write-expert-fact stream
                         "provider"
                         (capability-provider-capability provider)
                         (capability-provider-name provider)
                         (expert-type-name
                          (capability-provider-input-type provider))
                         (capability-provider-priority provider)))
    (when query-target
      (write-expert-fact stream "query_target" query-target))
    (when query-asset
      (write-expert-fact stream "query_asset" query-asset))))

(defun expert-temp-path ()
  (merge-pathnames
   (format nil "hackmode-expert-~d-~d.pl"
           (get-universal-time)
           (random 1000000000))
   (uiop:temporary-directory)))

(defun run-expert-goal (goal snapshot)
  (unless (expert-available-p)
    (error 'expert-unavailable :program *expert-program*))
  (let ((path (expert-temp-path)))
    (unwind-protect
         (progn
           (with-open-file (stream path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-string snapshot stream))
           (multiple-value-bind (stdout stderr status)
               (uiop:run-program
                (list *expert-program*
                      "-q"
                      "-f" (namestring (expert-rules-path))
                      "-s" (namestring path)
                      "-g" goal
                      "-t" "halt")
                :output :string
                :error-output :string
                :ignore-error-status t)
             (unless (or (null status) (zerop status))
               (error 'expert-query-failed :status status :stderr stderr))
             (or stdout "")))
      (when (probe-file path)
        (delete-file path)))))

(defun expert-classify-target (target &key
                                      (operation (current-operation))
                                      (assets (expert-current-assets))
                                      (providers (list-capability-providers)))
  "Classify TARGET using the Prolog expert rules and return a keyword.

TARGET is serialized only as a data fact; it cannot alter the executed Prolog
goal."
  (let* ((snapshot (expert-snapshot :operation operation
                                    :assets assets
                                    :providers providers
                                    :query-target target))
         (output (string-trim '(#\Space #\Tab #\Newline #\Return)
                              (run-expert-goal "emit_classification" snapshot))))
    (cond
      ((string= output "url") :url)
      ((string= output "domain") :domain)
      ((string= output "ipv4") :ipv4)
      ((string= output "ipv6") :ipv6)
      (t :unknown))))

(defun parse-expert-recommendation (line)
  (let ((parts (uiop:split-string line :separator '(#\Tab))))
    (unless (= 3 (length parts))
      (error 'expert-query-failed
             :status :invalid-output
             :stderr (format nil "Invalid expert recommendation row: ~s" line)))
    (make-expert-recommendation
     :priority (parse-integer (first parts))
     :capability (second parts)
     :provider (third parts))))

(defun expert-recommend-capabilities (asset-or-id &key
                                                    (operation (current-operation))
                                                    (assets (expert-current-assets))
                                                    (providers (list-capability-providers)))
  "Return deterministic Prolog recommendations for a canonical asset.

ASSET-OR-ID may be a Hackmode asset or its document ID. Recommendations are
advisory only; this function never executes a provider or writes operation state."
  (let* ((asset-id (etypecase asset-or-id
                     (meta (doc-id asset-or-id))
                     (string asset-or-id)))
         (snapshot (expert-snapshot :operation operation
                                    :assets assets
                                    :providers providers
                                    :query-asset asset-id))
         (output (run-expert-goal "emit_recommendations" snapshot)))
    (loop for line in (uiop:split-string output :separator '(#\Newline))
          for trimmed = (string-trim '(#\Space #\Tab #\Return) line)
          unless (zerop (length trimmed))
            collect (parse-expert-recommendation trimmed))))

(export '(+expert-engine-modes+
          +expert-effect-kinds+
          expert-engine
          make-expert-engine
          expert-engine-mode
          invalid-expert-engine-mode
          invalid-expert-engine-mode-value
          expert-effect-denied
          expert-effect-denied-engine
          expert-effect-denied-effect
          expert-engine-effect-authorized-p
          require-expert-engine-effect))
