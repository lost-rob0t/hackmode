(in-package :hackmode)


(defclass meta ()
  ((date-added :initarg :date-added :initform (unix-now) :type integer :accessor doc-date-added :allocation :class)
   (date-updated :initarg :date-updated :initform (unix-now) :type integer :accessor doc-date-updated :allocation :class)
   (operation :initarg :operation :initform "" :type string :accessor doc-operation :allocation :class)
   (dtype :initarg :dtype :initform nil :accessor doc-type :allocation :class)
   (tags :initarg :tags :type list :initform  () :accessor doc-tags :allocation :class)
   (doc-id :initarg :id :type string :initform (tek9:make-key-id) :allocation :class :accessor doc-id)))



(defclass output (meta)
  ((tool :initarg :tool :initform "" :type string :accessor doc-tool :allocation :class)
   (output :initarg :output :initform  "" :type string :accessor doc-output :allocation :class)))


(defclass domain (meta)
  ((domain :initarg :tool :initform "" :type string :accessor domain-name)
   (record-type :initarg :record-type :initform "" :type string :accessor domain-type)
   (zone :initarg :zone :initform "" :accessor doman-zone :type string)))


(defclass host (meta)
  ((hostname :initarg :hostname :type string :accessor doc-host :allocation :class)
   (ip :initarg :ip :type string :accessor doc-ip :allocation :class)))


(defclass port (meta)
  ((number :initarg :number :type integer :accessor doc-port :allocation :class)
   (services :initarg :services :type list :accessor doc-services :allocation :class)))


(defclass finding (meta)
  ((id :initarg :id :type string :initform "" :accessor finding-id :allocation :class)
   (doc-id :initarg :host :type string :initform "" :accessor finding-doc :allocation :class)
   (finding-type :initarg :finding-type :type string :initform "Bug" :accessor finding-finding-type :allocation :class)
   (date :initarg :date :type string :initform "" :accessor finding-date :allocation :class)))



(defclass url (meta)
  ((scheme :initarg :scheme :type string :accessor url-scheme :allocation :class)
   (host :initarg :host :type string :accessor url-host :allocation :class)
   (port :initarg :port :type integer :accessor url-port :allocation :class)
   (path :initarg :path :type string :accessor url-path :allocation :class)
   (query :initarg :query :type string :accessor url-query :allocation :class)))
