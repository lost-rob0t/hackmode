(in-package :hackmode-actors)

(defparameter *starintel-schema-version* "0.10.1"
  "StarIntel schema version stamped on every projected envelope.")

(defparameter *starintel-release* "0.10.1"
  "StarIntel release (starintel-core profile) this projection targets.")

(defparameter *starintel-dataset* hackmode:*starintel-dataset*
  "Default dataset for projected documents; mirrors the core runtime default.")

(defun starintel-timestring (unix-seconds)
  "Format UNIX-SECONDS as a stable UTC StarIntel timestamp string."
  (local-time:format-timestring
   nil
   (local-time:unix-to-timestamp unix-seconds)
   :format local-time:+iso-8601-format+
   :timezone local-time:+utc-zone+))

(defun make-starintel-envelope (id dataset dtype data &key
                                                       (tags nil tags-p)
                                                       (provenance nil provenance-p)
                                                       (date-added nil)
                                                       (date-updated nil))
  "Return a canonical StarIntel 0.10.1 envelope as a jsown object.

DATA is a jsown object holding the dtype payload with snake_case field names.
The envelope shape is the starintel-core 0.10.1 authority: _id, dataset, dtype,
schema_version, version, date_added, date_updated, sources, evidence, data."
  (declare (ignore tags-p provenance-p))
  (let ((envelope (jsown:empty-object)))
    (setf (jsown:val envelope "_id") id
          (jsown:val envelope "dataset") dataset
          (jsown:val envelope "dtype") dtype
          (jsown:val envelope "schema_version") *starintel-schema-version*
          (jsown:val envelope "version") 1
          (jsown:val envelope "date_added")
          (or (and date-added (starintel-timestring date-added))
              (starintel-timestring (hackmode:unix-now)))
          (jsown:val envelope "date_updated")
          (or (and date-updated (starintel-timestring date-updated))
              (starintel-timestring (hackmode:unix-now)))
          (jsown:val envelope "sources") '()
          (jsown:val envelope "evidence") '()
          (jsown:val envelope "data") data)
    (when tags
      (setf (jsown:val envelope "tags") tags))
    (when provenance
      (setf (jsown:val envelope "provenance") provenance))
    envelope))

(defun envelope-json (envelope)
  (jsown:to-json envelope))

(defun %alist->jsown-object (alist)
  "Convert a string-keyed alist into a jsown object.

Plain alists serialize as JSON arrays in jsown; header evidence maps must be
real JSON objects."
  (let ((object (jsown:empty-object)))
    (dolist (pair alist object)
      (setf (jsown:val object (car pair)) (cdr pair)))))

(defun %new-data-object (fields)
  "FIELDS is an alternating name/value list; returns a jsown object."
  (let ((object (jsown:empty-object)))
    (loop for (name value) on fields by #'cddr
          when value
            do (setf (jsown:val object name) value))
    object))

(defun %headers->jsown-object (headers)
  "Normalize HEADERS to a jsown object.

Accepts either an already-parsed jsown object ((:OBJ . alist)) or a plain
string-keyed alist."
  (cond
    ((and (consp headers) (eq (car headers) :obj))
     headers)
    ((null headers) nil)
    (t (%alist->jsown-object headers))))

(defun %asset-provenance (asset)
  (let ((provenance (jsown:empty-object)))
    (when (plusp (length (hackmode:doc-operation asset)))
      (setf (jsown:val provenance "operation") (hackmode:doc-operation asset)))
    (when (plusp (length (hackmode:doc-tool asset)))
      (setf (jsown:val provenance "producer") (hackmode:doc-tool asset)))
    provenance))

(defun %asset-envelope (asset dtype data)
  (make-starintel-envelope
   (hackmode:asset-deterministic-id asset)
   *starintel-dataset*
   dtype
   data
   :tags (copy-list (hackmode:doc-tags asset))
   :provenance (%asset-provenance asset)
   :date-added (hackmode:doc-date-added asset)
   :date-updated (hackmode:doc-date-updated asset)))

(defmethod asset->starintel-json ((asset hackmode:domain) &key (dataset *starintel-dataset*))
  "Return the StarIntel 0.10.1 JSON string for a resolved hackmode domain asset."
  (declare (ignore dataset))
  (hackmode:normalize-asset asset)
  (envelope-json
   (%asset-envelope
    asset "domain"
    (%new-data-object
     (list "domain" (hackmode:domain-name asset)
           "record" (hackmode:domain-name asset)
           "record_type" (hackmode:domain-type asset)
           "resolved_addresses" (copy-list (hackmode:domain-ips asset)))))))

(defmethod asset->starintel-json ((asset hackmode:host) &key (dataset *starintel-dataset*))
  "Return the StarIntel 0.10.1 JSON string for a resolved hackmode host asset.

Unresolved hostnames have no identity in StarIntel (identity is IP based) and
are not projected, matching the core runtime contract."
  (declare (ignore dataset))
  (hackmode:normalize-asset asset)
  (when (plusp (length (hackmode:doc-ip asset)))
    (envelope-json
     (%asset-envelope
      asset "host"
      (%new-data-object
       (list "hostname" (hackmode:doc-host asset)
             "ip" (hackmode:doc-ip asset)))))))

(defmethod asset->starintel-json ((asset hackmode:url) &key (dataset *starintel-dataset*))
  (declare (ignore dataset))
  (hackmode:normalize-asset asset)
  (envelope-json
   (%asset-envelope
    asset "url"
    (%new-data-object
     (list "url" (hackmode:asset-canonical-value asset)
           "path" (hackmode:url-path asset)
           "query" (hackmode:url-query asset))))))

(defmethod asset->starintel-json ((asset t) &key (dataset *starintel-dataset*))
  (declare (ignore dataset))
  nil)

(defun asset-starintel-supported-p (asset)
  "Return true when ASSET has a StarIntel 0.10.1 projection."
  (not (null (asset->starintel-json asset))))

(defun operation->starintel-json (operation &key
                                              (dataset *starintel-dataset*)
                                              (status "active")
                                              (phases nil phases-p))
  "Return the StarIntel 0.10.1 JSON string for a hackmode OPERATION.

The starintel-core 0.10.1 operation dtype requires mission, status, and
phases. MISSION comes from the operation description (falling back to the
name). PHASES defaults to a single visible recon seed phase rather than
inventing hidden history."
  (declare (ignore dataset))
  (let* ((name (hackmode:operation-name operation))
         (mission (or (hackmode:operation-description operation) name))
         (effective-phases
           (if phases-p
               phases
               (list (%new-data-object
                      (list "name" "recon" "status" status)))))
         (data (%new-data-object
                (list "mission" mission
                      "status" status
                      "phases" effective-phases
                      "targets" (list name))))
         (id (starintel:digest-id "hackmode-starintel-operation-v1" name)))
    (envelope-json
     (make-starintel-envelope id *starintel-dataset* "operation" data))))

(defun research-node->starintel-json (objective status &key
                                                       (description nil)
                                                       (operation nil)
                                                       (run-ids nil)
                                                       (dataset *starintel-dataset*))
  "Return the StarIntel 0.10.1 JSON string for a research node.

Research nodes are the starintel dtype for durable reasoning progress:
objective and status are required."
  (declare (ignore dataset))
  (let ((data (%new-data-object
               (list "objective" objective
                     "status" status
                     "description" description
                     "created_at" (starintel-timestring (hackmode:unix-now))
                     "run_ids" run-ids)))
        (id (starintel:digest-id "hackmode-starintel-research-node-v1"
                                 (or operation "") objective status)))
    (envelope-json
     (make-starintel-envelope id *starintel-dataset* "research-node" data))))

(defun http-transaction->starintel-json
    (transaction-id method url response-status &key
                     (scheme nil) (host nil) (path nil) (query nil) (port nil)
                     (http-version nil)
                     (request-headers nil) (response-headers nil)
                     (request-body-hash nil) (response-body-hash nil)
                     (started-at nil) (ended-at nil)
                     (provenance nil)
                     (dataset *starintel-dataset*))
  "Return the StarIntel 0.10.1 JSON string for one observed HTTP transaction.

REQUEST-HEADERS and RESPONSE-HEADERS are carried exactly as observed: capture
evidence is lossless by default and this projection must never redact,
sanitize, or drop header values."
  (declare (ignore dataset))
  (let ((data (%new-data-object
               (list "transaction_id" transaction-id
                     "method" method
                     "url" url
                     "response_status" response-status
                     "scheme" scheme
                     "host" host
                     "path" path
                     "query" query
                     "port" port
                     "http_version" http-version
                     "request_headers" (%headers->jsown-object request-headers)
                     "response_headers" (%headers->jsown-object response-headers)
                     "request_body_hash" request-body-hash
                     "response_body_hash" response-body-hash
                     "started_at" started-at
                     "ended_at" ended-at)))
        (id (starintel:digest-id "hackmode-starintel-http-transaction-v1"
                                 transaction-id)))
    (envelope-json
     (make-starintel-envelope id *starintel-dataset* "http-transaction" data
                                :provenance provenance))))

(defun %spool-headers (jsown-object)
  "Extract the raw headers map from a spool request/response object."
  (jsown:val-safe jsown-object "headers"))

(defun spool-object->starintel-transaction-json
    (spool-object &key (provenance nil) (dataset *starintel-dataset*))
  "Project one raw IPX spool object to a StarIntel 0.10.1 http-transaction.

SPOOL-OBJECT is the decoded append-only spool frame (jsown object) written by
the mitmproxy addon. Header maps are copied verbatim from the raw evidence."
  (declare (ignore dataset))
  (let* ((request (jsown:val spool-object "request"))
         (response (jsown:val spool-object "response"))
         (exchange-id (jsown:val spool-object "exchange_id"))
         (scheme (jsown:val request "scheme"))
         (host (jsown:val request "host"))
         (port (jsown:val request "port"))
         (path (jsown:val request "path"))
         (method (jsown:val request "method"))
         (status (jsown:val response "status_code"))
         (url (with-output-to-string (sink)
                (format sink "~a://~a~a" scheme host (or path ""))))
         (start (jsown:val spool-object "timestamp_start"))
         (end (jsown:val spool-object "timestamp_end")))
    (http-transaction->starintel-json
     exchange-id method url status
     :scheme scheme :host host :path path :port port
     :request-headers (%spool-headers request)
     :response-headers (%spool-headers response)
     :started-at (starintel-timestring (floor start))
     :ended-at (starintel-timestring (floor end))
     :provenance provenance)))

(defun visual-evidence->starintel-json (record &key
                                                (provenance nil)
                                                (dataset *starintel-dataset*))
  "Return the StarIntel 0.10.1 JSON string for a visual evidence record."
  (declare (ignore dataset))
  (let ((data (%new-data-object
               (list "capture_id" (hackmode-database:visual-evidence-record-record-id
                                   record)
                     "url" (or (hackmode-database:visual-evidence-record-final-url record)
                               (hackmode-database:visual-evidence-record-requested-url
                                record))
                     "screenshot_uri" (hackmode-database:visual-evidence-record-screenshot-evidence-ref
                                       record)
                     "screenshot_hash" (hackmode-database:visual-evidence-record-screenshot-digest
                                        record)
                     "title" (hackmode-database:visual-evidence-record-title record)
                     "status_code" (hackmode-database:visual-evidence-record-http-status
                                    record))))
        (id (starintel:digest-id "hackmode-visual-evidence-starintel-v1"
                                 (hackmode-database:visual-evidence-record-record-id
                                  record))))
    (envelope-json
     (make-starintel-envelope id *starintel-dataset* "web-capture" data
                                :provenance provenance))))

(defun enqueue-starintel-document (json dtype &key
                                             (database hackmode:*db*)
                                             (operation nil))
  "Durably enqueue one projected StarIntel JSON document for ingest."
  (hackmode:enqueue-starintel-json database json :operation operation))
