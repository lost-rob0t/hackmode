(defpackage :hackmode-actors
  (:nicknames :hm-actors)
  (:use :cl)
  (:export
   ;; Ontology access
   #:*ontology-spec-directory*
   #:ontology-error
   #:load-hackmode-ontology
   #:clear-hackmode-ontology
   #:hackmode-ontology-library
   #:hackmode-ontology-actors
   #:hackmode-ontology-manifest
   #:ontology-library-name
   #:ontology-actor-names
   #:ontology-actor-ir
   #:ontology-actor-accepts
   #:ontology-actor-produces
   #:ontology-actor-handler
   #:ontology-message-declaration
   #:ontology-document-names
   #:ontology-predicate-names
   #:ontology-declaration
   #:validate-ontology-message
   #:ontology-message-error
   #:make-ontology-wire-message
   #:ontology-wire-message-type
   #:ontology-wire-message-payload
   ;; StarIntel 0.10.1 projection
   #:*starintel-schema-version*
   #:*starintel-release*
   #:*starintel-dataset*
   #:make-starintel-envelope
   #:asset->starintel-json
   #:asset-starintel-supported-p
   #:operation->starintel-json
   #:research-node->starintel-json
   #:http-transaction->starintel-json
   #:spool-object->starintel-transaction-json
   #:visual-evidence->starintel-json
   #:enqueue-starintel-document
   ;; Actor system
   #:*ontology-actors*
   #:*asset-resolver*
   #:ensure-hackmode-ontology-actors
   #:stop-hackmode-ontology-actors
   #:hackmode-ontology-actor
   #:tell-hackmode-actor
   #:ask-hackmode-actor
   #:start-asset-projection-loop))
