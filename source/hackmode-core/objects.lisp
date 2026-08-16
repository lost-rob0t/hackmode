(in-package :hackmode)

;; Compatibility objects used by the historical Hackmode API.  State on these
;; objects must be instance-local.  The old :ALLOCATION :CLASS declarations
;; caused separate assets and operations to overwrite each other.
(defclass meta ()
  ((date-added :initarg :date-added :initform (unix-now) :type integer :accessor doc-date-added)
   (date-updated :initarg :date-updated :initform (unix-now) :type integer :accessor doc-date-updated)
   (operation :initarg :operation :initform "" :type string :accessor doc-operation)
   (dtype :initarg :dtype :initform nil :accessor doc-type)
   (tags :initarg :tags :type list :initform () :accessor doc-tags)
   (tool :initarg :tool :type string :initform "hackmode" :accessor doc-tool)
   (doc-id :initarg :id :type string :initform (tek9:make-key-id) :accessor doc-id)))

(defclass output (meta)
  ((tool :initarg :tool :initform "" :type string :accessor doc-tool)
   (output :initarg :output :initform "" :type string :accessor doc-output)))

(defclass domain (meta)
  ((ips :initarg :ips :initform nil :type list :accessor domain-ips)
   (record :initarg :record :initform "" :type string :accessor domain-name)
   (record-type :initarg :record-type :initform "" :type string :accessor domain-type)
   (zone :initarg :zone :initform "" :accessor doman-zone :type string)))

(defclass host (meta)
  ((hostname :initarg :hostname :initform "" :type string :accessor doc-host)
   (ip :initarg :ip :initform "" :type string :accessor doc-ip)))

(defclass port (meta)
  ((number :initarg :number :initform 0 :type integer :accessor doc-port)
   (services :initarg :services :initform nil :type list :accessor doc-services)))

(defclass finding (meta)
  ((id :initarg :finding-id :initform "" :type string :accessor finding-id)
   ;; Keep :HOST as a compatibility initarg, but do not shadow META's DOC-ID.
   (finding-document-id :initarg :document-id :initarg :host :initform ""
                        :type string :accessor finding-doc)
   (finding-type :initarg :finding-type :initform "Bug" :type string
                 :accessor finding-finding-type)
   (data :initarg :data :initform "" :type string :accessor finding-data)))

(defclass url (meta)
  ((scheme :initarg :scheme :initform "http" :type string :accessor url-scheme)
   (host :initarg :host :initform "" :type string :accessor url-host)
   (port :initarg :port :initform 80 :type integer :accessor url-port)
   (path :initarg :path :initform "" :type string :accessor url-path)
   (query :initarg :query :initform "" :type string :accessor url-query)))

(defclass cert (meta)
  ((not-before :initarg :not-before :type integer :accessor cert-not-before
               :initform (unix-now))
   (not-after :initarg :not-after :type integer :accessor cert-not-after
              :initform (unix-now))
   (common-name :initarg :common-name :type string :accessor cert-common-name
                :initform "")
   (org-unit-name :initarg :org-unit-name :type string :accessor cert-org-unit-name
                  :initform "")
   (locality :initarg :locality :type string :accessor cert-locality :initform "")
   (country-name :initarg :country :type string :accessor cert-country :initform "")
   (province :initarg :province :type string :accessor cert-province :initform "")))
