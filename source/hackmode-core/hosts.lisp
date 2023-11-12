(in-package :hackmode)

(defvar *hosts* (dict))

(defclass host ()
  ((id :initarg :id :type string :initform "" :accessor host-id)
   (domain :initarg :domain :type string :initform "" :accessor host-domain)
   (ip :initarg :ip :type string :initform "" :accessor host-ip)
   (ports :initarg :ports :type list :initform () :accessor host-ports)
   (tech :initarg :tech :type list :initform () :accessor host-tech)
   (tags :initarg :tags :type list :initform () :accessor host-tags)
   (urls :initarg :urls :type list :initform () :accessor host-urls)
   (date :initarg :date :type integer :initform (unix-now) :accessor host-date)))


(defclass finding ()
  (
   (id :initarg :id :type string :initform "" :accessor finding-id)
   (host :initarg :host :type string :initform "" :accessor finding-host)
   (finding-type :initarg :finding-type :type string :initform "Bug" :accessor finding-finding-type)
   (date :initarg :date :type string :initform "" :accessor finding-date)
   (url :initarg :url :type string :initform "" :accessor finding-url)))
