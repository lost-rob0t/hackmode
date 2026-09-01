(in-package :hackmode)

(defparameter +assets-by-type-view-name+ "assets/by-type")
(defparameter +assets-by-tag-view-name+ "assets/by-tag")

(defun investigation-view-selector (kind)
  (ecase kind
    (:by-type +assets-by-type-view-name+)
    (:by-tag +assets-by-tag-view-name+)))

(defun investigation-view-key-prefix (selector)
  (let ((value (string-downcase (string selector))))
    (format nil "~d:~a:" (length value) value)))

(defun investigation-view-key (selector document-id)
  (concatenate 'string
               (investigation-view-key-prefix selector)
               document-id))

(defun investigation-view-prefix-p (prefix key)
  (and (<= (length prefix) (length key))
       (string= prefix key :end2 (length prefix))))

(defun make-assets-by-type-view ()
  (tek9:new-view
   +assets-by-type-view-name+
   (lambda (document)
     (let* ((asset (tek9:doc-value document))
            (kind (and (typep asset 'meta)
                       (ignore-errors (asset-kind asset))))
            (id (and (typep asset 'meta) (doc-id asset))))
       (if (and kind (stringp id) (plusp (length id)))
           (list (cons (investigation-view-key kind id) id))
           nil)))))

(defun make-assets-by-tag-view ()
  (tek9:new-view
   +assets-by-tag-view-name+
   (lambda (document)
     (let* ((asset (tek9:doc-value document))
            (kind (and (typep asset 'meta)
                       (ignore-errors (asset-kind asset))))
            (id (and (typep asset 'meta) (doc-id asset))))
       (when (and kind (stringp id) (plusp (length id)))
         (loop for tag in (remove-duplicates
                           (mapcar (lambda (value)
                                     (string-downcase (string value)))
                                   (doc-tags asset))
                           :test #'string=)
               collect (cons (investigation-view-key tag id) id)))))))

(defun ensure-investigation-views (database &key rebuild)
  "Register Hackmode-owned asset investigation views in DATABASE.

When REBUILD is true, rebuild both views from canonical operation documents.
The view definitions stay in Hackmode; Tek9 remains the generic view engine."
  (unless (and database (tek9:db-is-open-p database))
    (error "Investigation views require an open operation database."))
  (labels ((ensure-view (name constructor)
             (or (gethash name (tek9:db-views database))
                 (tek9:add-view database (funcall constructor)))))
    (let ((by-type (ensure-view +assets-by-type-view-name+
                                #'make-assets-by-type-view))
          (by-tag (ensure-view +assets-by-tag-view-name+
                               #'make-assets-by-tag-view)))
      (when rebuild
        (tek9:apply-view-to-database database by-type)
        (tek9:apply-view-to-database database by-tag))
      (values by-type by-tag))))

(defun rebuild-investigation-views (database)
  "Rebuild every currently supported Hackmode investigation view."
  (ensure-investigation-views database :rebuild t)
  database)

(defun maintain-investigation-asset-views (database asset)
  "Incrementally project persisted ASSET into registered investigation views."
  (multiple-value-bind (by-type by-tag)
      (ensure-investigation-views database)
    (let ((id (doc-id asset)))
      (tek9:apply-view database by-type (list id))
      (tek9:apply-view database by-tag (list id))))
  asset)

(defun investigation-view-object (database kind)
  (ensure-investigation-views database)
  (or (gethash (investigation-view-selector kind) (tek9:db-views database))
      (error "Investigation view ~s is not registered." kind)))

(defun investigation-view-rows (database kind &key selector limit)
  "Return public decoded rows from investigation view KIND.

SELECTOR narrows :BY-TYPE or :BY-TAG using the deterministic materialized key
prefix. No Hackmode caller depends on Tek9's LMDB representation."
  (let* ((view (investigation-view-object database kind))
         (prefix (and selector (investigation-view-key-prefix selector)))
         (rows (if prefix
                   (tek9:view-rows database view
                                   :start prefix
                                   :end (concatenate 'string prefix
                                                     (string #\Rubout))
                                   :limit limit)
                   (tek9:view-rows database view :limit limit))))
    (if prefix
        (remove-if-not (lambda (row)
                         (investigation-view-prefix-p prefix (car row)))
                       rows)
        rows)))

(defun investigation-view-asset-ids (database kind selector &key limit)
  "Return stable asset IDs selected through materialized investigation view KIND."
  (mapcar #'cdr
          (investigation-view-rows database kind
                                   :selector selector
                                   :limit limit)))
