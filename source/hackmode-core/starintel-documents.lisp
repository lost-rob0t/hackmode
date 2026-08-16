(in-package :hackmode)

(defparameter *starintel-dataset* "star-intel"
  "Default StarIntel dataset used when projecting Hackmode assets.")

(defun asset-starintel-provenance (asset)
  "Return StarIntel provenance metadata for ASSET."
  (let ((provenance (jsown:empty-object)))
    (when (plusp (length (doc-operation asset)))
      (setf (jsown:val provenance "operation") (doc-operation asset)))
    (when (plusp (length (doc-tool asset)))
      (setf (jsown:val provenance "producer") (doc-tool asset)))
    provenance))

(defun unix-seconds->starintel-timestring (seconds)
  "Format Unix SECONDS as a stable UTC StarIntel timestamp string."
  (local-time:format-timestring
   nil
   (local-time:unix-to-timestamp seconds)
   :format local-time:+iso-8601-format+
   :timezone local-time:+utc-zone+))

(defun asset-starintel-common-initargs (asset)
  "Return shared StarIntel document initargs for ASSET.

Carry Hackmode's persisted timestamps into the projection so serializing the
same asset repeatedly does not create a different outbox payload merely because
the projection happened at a later wall-clock time."
  (list :tags (copy-list (doc-tags asset))
        :date-added (unix-seconds->starintel-timestring (doc-date-added asset))
        :date-updated (unix-seconds->starintel-timestring (doc-date-updated asset))
        :provenance (asset-starintel-provenance asset)))

(defmethod asset->starintel-document ((asset domain) &key (dataset *starintel-dataset*))
  (normalize-asset asset)
  (apply #'starintel:new-domain
         dataset
         :record (domain-name asset)
         :record-type (domain-type asset)
         :resolved (copy-list (domain-ips asset))
         (asset-starintel-common-initargs asset)))

(defmethod asset->starintel-document ((asset host) &key (dataset *starintel-dataset*))
  (normalize-asset asset)
  ;; star-cl currently hashes HOST identity from IP only. Do not project an
  ;; unresolved hostname as an empty-IP canonical document because every such
  ;; hostname would collapse to the same StarIntel ID.
  (when (plusp (length (doc-ip asset)))
    (apply #'starintel:new-host
           dataset
           :hostname (doc-host asset)
           :ip (doc-ip asset)
           (asset-starintel-common-initargs asset))))

(defmethod asset->starintel-document ((asset url) &key (dataset *starintel-dataset*))
  (normalize-asset asset)
  (apply #'starintel:new-url
         dataset
         :url (asset-canonical-value asset)
         :path (url-path asset)
         :query (url-query asset)
         (asset-starintel-common-initargs asset)))

(defun asset->starintel-json (asset &key (dataset *starintel-dataset*))
  "Return ASSET encoded as a canonical StarIntel v0.9 JSON object.

Return NIL when the compatibility asset has no safe StarIntel projection yet."
  (let ((document (asset->starintel-document asset :dataset dataset)))
    (when document
      (starintel:encode document))))

(defun asset-starintel-supported-p (asset)
  "Return true when ASSET currently has a safe StarIntel document projection."
  (not (null (asset->starintel-document asset))))
