(in-package :hackmode)

(defstruct asset-event
  event-type
  asset
  operation
  timestamp)

(defvar *asset-event-hook*
  (make-instance 'nhooks:hook-any :handlers nil)
  "Generic persisted-asset event hook. Handlers receive one ASSET-EVENT.")

(defgeneric asset-kind (asset)
  (:documentation "Return the canonical Hackmode asset type string."))

(defgeneric normalize-asset (asset)
  (:documentation "Normalize ASSET in place and return it."))

(defgeneric asset-canonical-value (asset)
  (:documentation "Return the deterministic identity input for ASSET."))

(defgeneric asset-requires-parent-p (asset)
  (:documentation "Whether ASSET identity requires a parent asset id."))

(defgeneric asset->starintel-document (asset &key dataset)
  (:documentation
   "Project ASSET to the canonical StarIntel document model when supported."))

(defmethod asset-requires-parent-p ((asset t))
  (declare (ignore asset))
  nil)

(defmethod asset->starintel-document ((asset t) &key dataset)
  (declare (ignore asset dataset))
  nil)

(defun normalize-name (value)
  (string-downcase
   (string-trim '(#\Space #\Tab #\Newline #\Return) (or value ""))))

(defun normalize-domain-name (value)
  (string-right-trim '(#\.) (normalize-name value)))

(defmethod asset-kind ((asset domain)) "domain")
(defmethod normalize-asset ((asset domain))
  (setf (domain-name asset) (normalize-domain-name (domain-name asset))
        (domain-type asset) (string-upcase (string-trim " " (or (domain-type asset) "")))
        (doc-type asset) "domain")
  asset)
(defmethod asset-canonical-value ((asset domain))
  (format nil "~a|~a" (domain-name asset) (domain-type asset)))

(defmethod asset-kind ((asset host)) "host")
(defmethod normalize-asset ((asset host))
  (setf (doc-host asset) (normalize-domain-name (doc-host asset))
        (doc-ip asset) (string-trim " " (or (doc-ip asset) ""))
        (doc-type asset) "host")
  asset)
(defmethod asset-canonical-value ((asset host))
  ;; StarIntel's current host identity is IP-based. Preserve unresolved hostnames
  ;; locally until they can be projected without collapsing onto the empty IP.
  (if (plusp (length (doc-ip asset)))
      (doc-ip asset)
      (doc-host asset)))

(defmethod asset-kind ((asset url)) "url")
(defmethod normalize-asset ((asset url))
  (setf (url-scheme asset) (normalize-name (or (url-scheme asset) "http"))
        (url-host asset) (normalize-domain-name (url-host asset))
        (url-path asset) (or (url-path asset) "")
        (url-query asset) (or (url-query asset) "")
        (doc-type asset) "url")
  asset)
(defmethod asset-canonical-value ((asset url))
  (with-output-to-string (out)
    (format out "~a://~a" (url-scheme asset) (url-host asset))
    (unless (or (and (string= (url-scheme asset) "http") (= (url-port asset) 80))
                (and (string= (url-scheme asset) "https") (= (url-port asset) 443)))
      (format out ":~d" (url-port asset)))
    (write-string (url-path asset) out)
    (when (plusp (length (url-query asset)))
      (write-char #\? out)
      (write-string (url-query asset) out))))

(defmethod asset-kind ((asset cert)) "certificate")
(defmethod normalize-asset ((asset cert))
  (setf (cert-common-name asset) (normalize-domain-name (cert-common-name asset))
        (doc-type asset) "certificate")
  asset)
(defmethod asset-canonical-value ((asset cert))
  (format nil "~a|~d|~d"
          (cert-common-name asset)
          (cert-not-before asset)
          (cert-not-after asset)))

(defmethod asset-kind ((asset finding)) "finding")
(defmethod normalize-asset ((asset finding))
  (setf (doc-type asset) "finding")
  asset)
(defmethod asset-canonical-value ((asset finding))
  (format nil "~a|~a|~a"
          (finding-finding-type asset)
          (finding-doc asset)
          (finding-data asset)))

(defmethod asset-kind ((asset port)) "port")
(defmethod normalize-asset ((asset port))
  (setf (doc-type asset) "port")
  asset)
(defmethod asset-canonical-value ((asset port))
  (princ-to-string (doc-port asset)))
(defmethod asset-requires-parent-p ((asset port))
  (declare (ignore asset))
  t)

(defun asset-starintel-id (asset)
  "Return StarIntel's canonical document ID for ASSET when projection exists."
  (let ((document (asset->starintel-document asset)))
    (when document
      (starintel:doc-id document))))

(defun asset-deterministic-id (asset &key parent-id)
  "Return the canonical deterministic ID for ASSET.

When ASSET projects to a StarIntel document, use that document's own ID rule so
local Hackmode and central StarIntel address the same logical record identically.
PARENT-ID is required for child assets such as ports that have no standalone
canonical StarIntel document identity yet. Unsupported compatibility assets use
STARINTEL:DIGEST-ID as a local deterministic fallback."
  (when (and (asset-requires-parent-p asset) (not parent-id))
    (error "Asset type ~a requires :PARENT-ID for deterministic identity."
           (asset-kind asset)))
  (or (and (null parent-id) (asset-starintel-id asset))
      (if parent-id
          (starintel:digest-id (asset-kind asset)
                               parent-id
                               (asset-canonical-value asset))
          (starintel:digest-id (asset-kind asset)
                               (asset-canonical-value asset)))))

(defun bind-asset-operation (asset)
  (when (and (string= (doc-operation asset) "") *current-operation*)
    (setf (doc-operation asset) (operation-name *current-operation*)))
  asset)

(defun publish-legacy-asset-hook (asset)
  "Dispatch persisted ASSET to compatibility hooks.

New code should subscribe to `*asset-event-hook*'. These hooks remain only for
older recon/client integrations while they migrate to the generic event stream."
  (typecase asset
    (domain (nhooks:run-hook *domain-hook* asset))
    (finding (nhooks:run-hook *finding-hook* asset)))
  asset)

(defun publish-asset-event (event-type asset)
  "Publish EVENT-TYPE for already-persisted ASSET."
  (let ((event (make-asset-event
                :event-type event-type
                :asset asset
                :operation (doc-operation asset)
                :timestamp (unix-now))))
    (nhooks:run-hook *asset-event-hook* event)
    (publish-legacy-asset-hook asset)
    event))

(defun subscribe-asset-events (handler)
  "Subscribe HANDLER to the generic asset event stream."
  (nhooks:add-hook *asset-event-hook* handler)
  handler)

(defun store-asset (asset &key (database *db*) parent-id)
  "Normalize and persist ASSET into the active operation store."
  (normalize-asset asset)
  (bind-asset-operation asset)
  (setf (doc-id asset) (asset-deterministic-id asset :parent-id parent-id))
  (put-doc asset :database database)
  asset)

(defun discover-asset (asset &key (database *db*) parent-id (publish t))
  "Persist ASSET exactly once, then publish a :DISCOVERED event.

Returns two values: the canonical stored asset and true only when this call
created it. Persistence happens before event publication, so subscribers never
observe an asset that is absent from the local operation store."
  (unless (and database (tek9:db-is-open-p database))
    (error "DISCOVER-ASSET requires an open local operation database."))
  (normalize-asset asset)
  (bind-asset-operation asset)
  (setf (doc-id asset) (asset-deterministic-id asset :parent-id parent-id))
  (let ((existing (tek9:fetch* database (doc-id asset))))
    (if existing
        (values existing nil)
        (progn
          (put-doc asset :database database)
          (when publish
            (publish-asset-event :discovered asset))
          (values asset t)))))

(defun record-recon-asset (asset &key (database *db*) parent-id)
  "Accept ASSET from a recon provider without forcing a standalone DB mode.

When DATABASE is open, route through the canonical persisted discovery path and
return ASSET, CREATED-P, T. Without an operation store, normalize the object and
run only the legacy compatibility hook, returning ASSET, NIL, NIL. Generic asset
events are never published for unpersisted results."
  (if (and database (tek9:db-is-open-p database))
      (multiple-value-bind (stored created-p)
          (discover-asset asset :database database :parent-id parent-id)
        (values stored created-p t))
      (progn
        (normalize-asset asset)
        (publish-legacy-asset-hook asset)
        (values asset nil nil))))

(defun query-assets (&key (database *db*) type predicate)
  "Return operation-local assets matching TYPE and PREDICATE.

This first protocol slice intentionally uses Tek9's existing snapshot iterator.
Indexes/views can be added without changing callers once query volume requires
it."
  (unless (and database (tek9:db-is-open-p database))
    (error "QUERY-ASSETS requires an open local operation database."))
  (let ((wanted (and type (string-downcase (string type))))
        assets)
    (tek9:map-database
     database
     :map-fn
     (lambda (key document)
       (declare (ignore key))
       (let* ((value (tek9:doc-value document))
              (kind (and (typep value 'meta)
                         (ignore-errors (asset-kind value)))))
         (when (and kind
                    (or (null wanted) (string= wanted kind))
                    (or (null predicate) (funcall predicate value)))
           (push value assets)))))
    (nreverse assets)))
