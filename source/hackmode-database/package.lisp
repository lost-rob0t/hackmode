(uiop:define-package :hackmode-database
  (:nicknames :hack-db)
  (:use :cl)
  (:export
   #:*db*
   #:execution-graph-validation-error
   #:execution-record
   #:execution-record-kind
   #:execution-record-operation-id
   #:execution-record-run-id
   #:execution-record-call-id
   #:execution-record-record-id
   #:execution-record-capability-id
   #:execution-record-status
   #:execution-record-payload
   #:execution-record-provenance
   #:make-tool-call-record
   #:make-tool-result-record
   #:validate-tool-result-link
   #:execution-graph-name
   #:execution-record->tek9-node
   #:tool-result-link-edge
   #:persist-execution-record
   #:persist-tool-execution
   #:put-doc
   #:put-docs))
