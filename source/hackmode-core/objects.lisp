(in-package :hackmode)


(defclass meta ()
  ((date-added :initarg :date-added :initform (unix-now) :type integer :accessor doc-date-added)
   (date-updated :initarg :date-updated :initform (unix-now) :type integer :accessor doc-date-updated)
   (operation :initarg :operation :initform "" :type string :accessor doc-operation)
   (dtype :initarg :dtype :initform nil :accessor doc-type)
   (tags :initarg :tags :type list :initform  () :accessor doc-tags)
   (doc-id :initarg :id :type string :initform (tek9:make-key-id))))



(export 'meta)
(defclass output (meta)
  ((tool :initarg :tool :initform "" :type string :accessor doc-tool)
   (output :initarg :output :initform  "" :type string :accessor doc-output)
   (dtype :initform 'output :accessor doc-dtype)))

(export 'output)

(defclass host (meta)
  ((hostname :initarg :hostname :type string :accessor doc-host)
   (ip :initarg :ip :type string :accessor doc-ip)))

(export 'host)

(defclass port ()
  ((number :initarg :number :type integer :accessor doc-port)
   (services :initarg :services :type list :accessor doc-services)))
(export 'port)


(defclass finding ()
  ((id :initarg :id :type string :initform "" :accessor finding-id)
   (doc-id :initarg :host :type string :initform "" :accessor finding-doc)
   (finding-type :initarg :finding-type :type string :initform "Bug" :accessor finding-finding-type)
   (date :initarg :date :type string :initform "" :accessor finding-date)))

(export 'finding)
