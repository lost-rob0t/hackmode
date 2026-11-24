(in-package :hackmode-mcp)

;;;; Transport projection of persisted Hackmode assets.
;;;;
;;;; This is the JSON view of assets for MCP results, not a second storage
;;;; model: canonical evidence stays in the operation store, and every field
;;;; the transport view carries is projected from the stored asset.

(defun input-type-name (type)
  "Render a provider input/output TYPE designator as a readable string."
  (cond
    ((null type) :null)
    ((symbolp type)
     (format nil "~(~a~):~(~a~)" (package-name (symbol-package type)) type))
    (t (format nil "~a" type))))

(defun project-asset (asset)
  "Return the JSON projection of one persisted Hackmode ASSET."
  (let ((object
          (list :obj
                (cons "id" (hackmode:doc-id asset))
                (cons "kind" (hackmode:asset-kind asset))
                (cons "operation" (hackmode:doc-operation asset))
                (cons "tool" (hackmode:doc-tool asset))
                (cons "tags" (copy-list (hackmode:doc-tags asset)))
                (cons "dateAdded" (hackmode:doc-date-added asset))
                (cons "dateUpdated" (hackmode:doc-date-updated asset))
                (cons "value" (hackmode:asset-canonical-value asset)))))
    (typecase asset
      (hackmode:domain
       (nconc object
              (list (cons "name" (hackmode:domain-name asset))
                    (cons "recordType" (hackmode:domain-type asset))
                    (cons "ips" (copy-list (hackmode:domain-ips asset))))))
      (hackmode:host
       (nconc object
              (list (cons "hostname" (hackmode:doc-host asset))
                    (cons "ip" (hackmode:doc-ip asset)))))
      (hackmode:url
       (nconc object
              (list (cons "scheme" (hackmode:url-scheme asset))
                    (cons "host" (hackmode:url-host asset))
                    (cons "port" (hackmode:url-port asset))
                    (cons "path" (hackmode:url-path asset))
                    (cons "query" (hackmode:url-query asset)))))
      (hackmode:finding
       (nconc object
              (list (cons "findingType" (hackmode:finding-finding-type asset))
                    (cons "findingDoc" (hackmode:finding-doc asset))
                    (cons "data" (hackmode:finding-data asset)))))
      (hackmode:cert
       (nconc object
              (list (cons "commonName" (hackmode:cert-common-name asset))
                    (cons "notBefore" (hackmode:cert-not-before asset))
                    (cons "notAfter" (hackmode:cert-not-after asset)))))
      (hackmode:port
       (nconc object
              (list (cons "port" (hackmode:doc-port asset))
                    (cons "services" (copy-list (hackmode:doc-services asset)))))))
    object))
