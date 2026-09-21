(uiop:define-package :hackmode-bbp
  (:use :cl)
  (:export
   :bbp-target
   :make-bbp-target
   :bbp-target-id
   :bbp-target-actor
   :bbp-target-value
   :bbp-target-dataset
   :bbp-target-sources
   :bbp-target-options
   :bbp-scan-result
   :bbp-scan-result-target
   :bbp-scan-result-state
   :bbp-scan-result-job-id
   :bbp-scan-result-assets
   :bbp-scan-result-documents
   :bbp-scan-result-relations
   :bbp-scan-result-error
   :bbp-target-plan
   :start-bbp-supervisor
   :stop-bbp-supervisor
   :dispatch-bbp-target
   :*bbp-supervisor*))

(in-package :hackmode-bbp)
