(spec-library "dev.hackmode/core@1"
  (:version "0.10.1")

  ;; The canonical StarIntel vocabulary is consumed, not redefined. The
  ;; vendored copy below is byte-identical to
  ;; lost-rob0t/starintel-gpt-auto-dig spec/star/starintel-core-0.10.1.star
  ;; (served at https://spec.starintel.actor/star/0.10.1) and is digest
  ;; locked. Runtime dtype support is validated against the compiled
  ;; starintel core graph.
  (import "org.starintel/core@1"
    :version "0.10.1"
    :digest "sha256:0c6a50a12a9779a0e760cd48d6e4f3bf3fdadf04e61ec3cb67f8685fe64499a5"
    :path "vendor/starintel-core-0.10.1.star")

  (scalar hackmode-id
    (:base string
     :pattern "^[A-Za-z0-9._~:/+-]{1,512}$"))

  (scalar unix-time
    (:base integer
     :minimum 0))

  (scalar port-number
    (:base integer
     :minimum 0
     :maximum 65535))

  (enum asset-kind
    (domain host port finding url cert http-exchange visual-evidence))

  (enum outbox-state-kind
    (queued sending retry failed quarantined acknowledged))

  (enum capture-state-kind
    (stopped running restarting failed))

  (enum provider-status
    (pending running succeeded failed))

  (enum module-catalog-detail-kind (summary full))
  (enum module-catalog-status-kind (ok not-found invalid-request unsupported))
  (enum module-catalog-command-kind (families list describe))
  (enum module-catalog-projection-kind (summary none))

  ;; A bounded projection of the local catalog, not a StarIntel dtype.
  (document module-summary
    (:persistence transient)
    (schemaVersion integer :required)
    (id string :required)
    (version string :required)
    (family string :required)
    (title string :required)
    (description string :required)
    (authors (list string) :required)
    (tags (list string) :required)
    (references (list string) :required)
    (platforms (list string) :required)
    (architectures (list string) :required)
    (capability string :optional)
    (provider string :optional)
    (sessionTypes (list string) :required)
    (compatiblePayloads (list string) :required)
    (lifecycle string :required))

  (document hackmode-document
    (:persistence persistent)
    (id hackmode-id :required)
    (dataset string :required)
    (dtype string :required)
    (schemaVersion string :required)
    (operation string :optional)
    (tool string :optional)
    (tags (list string) :optional)
    (dateAdded string :optional)
    (dateUpdated string :optional)
    (provenance map :optional))

  (document operation
    (:extends hackmode-document
     :persistence persistent)
    (name string :required)
    (mission string :required)
    (status string :required)
    (phases (list map) :required)
    (targets (list string) :optional)
    (inScope (list string) :optional)
    (outOfScope (list string) :optional))

  (document domain
    (:extends hackmode-document
     :persistence persistent)
    (name string :required)
    (recordType string :optional)
    (record string :optional)
    (resolved (list string) :optional))

  (document host
    (:extends hackmode-document
     :persistence persistent)
    (hostname string :optional)
    (ip string :required))

  (document url
    (:extends hackmode-document
     :persistence persistent)
    (url string :required)
    (path string :optional)
    (query string :optional))

  (document port
    (:extends hackmode-document
     :persistence persistent)
    (number port-number :required)
    (transport string :optional)
    (state string :optional)
    (hostId hackmode-id :optional))

  (document finding
    (:extends hackmode-document
     :persistence persistent)
    (title string :required)
    (severity string :optional)
    (status string :optional)
    (assetId hackmode-id :optional))

  (document http-exchange
    (:extends hackmode-document
     :persistence persistent)
    (transactionId string :required)
    (method string :required)
    (url string :required)
    (responseStatus integer :required)
    (scheme string :optional)
    (host string :optional)
    (path string :optional)
    (query string :optional)
    (port port-number :optional)
    (httpVersion string :optional)
    (requestHeaders map :optional)
    (responseHeaders map :optional)
    (requestBodyHash string :optional)
    (responseBodyHash string :optional)
    (startedAt string :optional)
    (endedAt string :optional))

  (document visual-evidence
    (:extends hackmode-document
     :persistence persistent)
    (captureId string :required)
    (url string :required)
    (screenshotUri string :required)
    (screenshotHash string :required)
    (title string :optional)
    (statusCode integer :optional)
    (browser string :optional)
    (capturedAt string :optional))

  (document research-node
    (:extends hackmode-document
     :persistence persistent)
    (objective string :required)
    (status string :required)
    (description string :optional)
    (createdAt string :optional)
    (runIds (list string) :optional))

  (document capture-session
    (:persistence transient)
    (id hackmode-id :required)
    (state capture-state-kind :required)
    (spoolPath string :optional)
    (restarts integer :optional))

  (document provider-job
    (:persistence transient)
    (id hackmode-id :required)
    (capability string :required)
    (status provider-status :required)
    (provider string :optional)
    (input map :optional)
    (outputAssetIds (list hackmode-id) :optional))

  (document outbox-entry
    (:persistence transient)
    (id hackmode-id :required)
    (dtype string :required)
    (state outbox-state-kind :required)
    (attempts integer :optional)
    (lastError string :optional))

  (predicate resolves-to
    (:source domain
     :destination host))

  (predicate hosted-on
    (:source port
     :destination host))

  (predicate serves-url
    (:source host
     :destination url))

  (predicate discovered-in
    (:source hackmode-document
     :destination operation))

  (predicate observed-in
    (:source http-exchange
     :destination operation))

  (predicate evidence-of
    (:source http-exchange
     :destination hackmode-document))

  (predicate produced-by
    (:source hackmode-document
     :destination provider-job))

  (message hackmode/discover-asset@1
    (:fields
     ((asset reference :required))))

  (message hackmode/module-families-request@1
    (:fields ((requestId string :required) (operationId string :optional))))

  (message hackmode/module-list-request@1
    (:fields
     ((requestId string :required)
      (operationId string :optional)
      (family string :optional)
      (query string :optional)
      (tags (list string) :optional)
      (capability string :optional)
      (detail module-catalog-detail-kind :optional))))

  (message hackmode/module-describe-request@1
    (:fields
     ((requestId string :required)
      (operationId string :optional)
      (moduleId string :required)
      (moduleVersion string :required)
      (detail module-catalog-detail-kind :optional))))

  (message hackmode/module-catalog-result@1
    (:fields
     ((requestId string :required)
      (operationId string :optional)
      (command module-catalog-command-kind :required)
      (status module-catalog-status-kind :required)
      (projection module-catalog-projection-kind :required)
      (omittedFields (list string) :required)
      (families (list string) :optional)
      (modules (list module-summary) :optional)
      (module module-summary :optional)
      (errorField string :optional)
      (errorReason string :optional))))

  (message hackmode/asset-discovered@1
    (:fields
     ((assetId string :required)
      (kind asset-kind :required))))

  (message hackmode/run-capability@1
    (:fields
     ((capability string :required)
      (input map :required))))

  (message hackmode/provider-result@1
    (:fields
     ((jobId string :required)
      (status string :required)
      (assets (list reference) :required))))

  (message hackmode/enqueue-document@1
    (:fields
     ((json string :required)
      (dtype string :required))))

  (message hackmode/drain-outbox@1
    (:fields ()))

  (message hackmode/outbox-state@1
    (:fields
     ((queued integer :required)
      (failed integer :required))))

  (message hackmode/start-capture@1
    (:fields
     ((spec map :required))))

  (message hackmode/stop-capture@1
    (:fields ()))

  (message hackmode/capture-state@1
    (:fields
     ((state capture-state-kind :required)
      (spoolPath string :optional))))

  (message hackmode/replay-spool@1
    (:fields
     ((spoolPath string :required)
      (operationId string :required)
      (captureSessionId string :required)
      (sourceId string :required))))

  (message hackmode/classify-target@1
    (:fields
     ((target string :required))))

  (message hackmode/recommend-capabilities@1
    (:fields
     ((target string :required))))

  (message hackmode/expert-recommendation@1
    (:fields
     ((capability string :required)
      (reason string :optional)))))
