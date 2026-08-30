(in-package :hackmode-tests)

(defun run-rage-worker-scope-test ()
  (let ((passive (hackmode:make-rage-worker
                  :id "rage-recon"
                  :run-id "run-001"
                  :operation "bbp-starintel"
                  :mode :passive
                  :objective '(:finding-required t)))
        (active (hackmode:make-rage-worker
                 :id "rage-active"
                 :run-id "run-002"
                 :operation "bbp-starintel"
                 :mode :active
                 :objective '(:foothold-required t))))
    (assert-equal :passive (hackmode:rage-worker-mode passive)
                  "passive worker mode")
    (assert-equal :active (hackmode:rage-worker-mode active)
                  "active worker mode")
    (assert (not (string= (hackmode:rage-worker-run-id passive)
                          (hackmode:rage-worker-run-id active)))
            ()
            "Separate workers must retain separate run identities."))

  ;; Migrated workers must not fall back into ordinary StarIntel engineering.
  (let* ((item (hackmode:make-rage-work-item
                :kind :implementation
                :scope :starintel
                :description "Implement an approved StarIntel feature issue"
                :operation-authorized-p t
                :source "lost-rob0t/starintel-server#999"))
         (decision (hackmode:authorize-rage-work-item item)))
    (assert (not (hackmode:rage-scope-decision-allowed-p decision)))
    (assert-equal :starintel-cyber-only
                  (hackmode:rage-scope-decision-reason decision)
                  "StarIntel engineering rejection"))

  ;; StarIntel is valid as an explicitly authorized BBP/security target.
  (dolist (kind '(:recon
                  :source-security-review
                  :cve-correlation
                  :fuzzing
                  :security-projection))
    (let* ((item (hackmode:make-rage-work-item
                  :kind kind
                  :scope :starintel
                  :description "Authorized StarIntel BBP work"
                  :operation-authorized-p t
                  :target "starintel.actor"))
           (decision (hackmode:authorize-rage-work-item item)))
      (assert (hackmode:rage-scope-decision-allowed-p decision)
              ()
              "Expected StarIntel cyber work ~s to be accepted." kind)
      (assert-equal :authorized
                    (hackmode:rage-scope-decision-reason decision)
                    "StarIntel cyber authorization")))

  ;; Cyber vocabulary never overrides the containing operation's authorization.
  (let* ((item (hackmode:make-rage-work-item
                :kind :recon
                :scope :starintel
                :operation-authorized-p nil))
         (decision (hackmode:authorize-rage-work-item item)))
    (assert (not (hackmode:rage-scope-decision-allowed-p decision)))
    (assert-equal :operation-not-authorized
                  (hackmode:rage-scope-decision-reason decision)
                  "operation scope rejection"))

  ;; This migrated worker class is cyber-only even for non-StarIntel sources.
  (let* ((item (hackmode:make-rage-work-item
                :kind :architecture
                :scope :external
                :operation-authorized-p t))
         (decision (hackmode:authorize-rage-work-item item)))
    (assert (not (hackmode:rage-scope-decision-allowed-p decision)))
    (assert-equal :non-cyber-work
                  (hackmode:rage-scope-decision-reason decision)
                  "generic engineering rejection"))

  ;; RLM/LLM escalation is not a new worker authority mode in this foundation.
  (let ((signaled nil))
    (handler-case
        (hackmode:make-rage-worker
         :id "rage-llm"
         :run-id "run-003"
         :operation "bbp"
         :mode :llm)
      (error ()
        (setf signaled t)))
    (assert signaled ()
            "Unsupported RAGE worker modes must fail closed.")))

(defun run-rage-worker-tests ()
  (run-rage-worker-scope-test)
  t)
