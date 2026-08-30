(in-package :hackmode)

(defparameter +expert-recon-id+ "recon")
(defparameter +expert-recon-version+ "1")

(defun parse-expert-recon-candidate (output)
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return)
                              (or output ""))))
    (when (plusp (length trimmed))
      (let ((parts (uiop:split-string trimmed :separator '(#\Tab))))
        (unless (= 3 (length parts))
          (error 'expert-query-failed
                 :status :invalid-output
                 :stderr (format nil "Invalid recon candidate row: ~s" trimmed)))
        (list :priority (parse-integer (first parts))
              :capability (second parts)
              :provider (third parts))))))

(defun expert-recon-next-action (asset &key
                                         (operation (current-operation))
                                         run-id
                                         (assets (expert-current-assets))
                                         (providers (list-capability-providers))
                                         execution-records
                                         operational-kb-entries
                                         (expert-version +expert-recon-version+)
                                         evidence-ids)
  "Return the next typed recon dispatch action for ASSET, or NIL.

The recon expert selects one deterministic compatible recon provider through a
fixed Prolog goal. This function constructs a typed action only: it does not
execute providers or mutate canonical state. Execution remains behind the
existing active-action/provider boundary."
  (check-type asset meta)
  (unless operation
    (error "EXPERT-RECON-NEXT-ACTION requires an operation."))
  (unless (expert-action-string-p run-id)
    (error "EXPERT-RECON-NEXT-ACTION requires a non-empty run ID."))
  (unless (expert-action-string-p (doc-id asset))
    (error "EXPERT-RECON-NEXT-ACTION requires an asset with a stable document ID."))
  (let* ((snapshot
           (expert-snapshot
            :operation operation
            :assets assets
            :providers providers
            :query-asset (doc-id asset)
            :execution-records execution-records
            :operational-kb-entries operational-kb-entries))
         (candidate
           (parse-expert-recon-candidate
            (run-expert-goal "emit_recon_next_action" snapshot))))
    (when candidate
      (let ((capability (getf candidate :capability))
            (provider (getf candidate :provider)))
        (make-expert-active-action
         :id (format nil "recon:~a:~a:~a:~a:~a"
                     (operation-name operation)
                     run-id
                     (doc-id asset)
                     capability
                     provider)
         :kind :dispatch
         :operation (operation-name operation)
         :run-id run-id
         :expert-id +expert-recon-id+
         :expert-version expert-version
         :evidence-ids evidence-ids
         :payload
         (make-expert-dispatch-payload
          :capability capability
          :provider provider
          :input asset))))))

(export '(+expert-recon-id+
          +expert-recon-version+
          expert-recon-next-action))
