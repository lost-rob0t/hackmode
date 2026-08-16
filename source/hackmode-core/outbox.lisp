(in-package :hackmode)

(defconstant +outbox-database-name+ "outbox")
(defconstant +outbox-id-version+ "hackmode-outbox-v1")

(defparameter *outbox-max-attempts* 8
  "Maximum delivery attempts before an outbox entry becomes FAILED.")

(defparameter *outbox-backoff-base-seconds* 2
  "Base delay for deterministic exponential outbox retry backoff.")

(defparameter *outbox-backoff-max-seconds* 300
  "Maximum outbox retry delay in seconds.")

(defparameter *starintel-ingest-base-url* "http://127.0.0.1:5000"
  "Default StarIntel Server URL used by the HTTP outbox transport.")

(define-condition outbox-transport-error (error)
  ((message :initarg :message :reader outbox-transport-error-message))
  (:report (lambda (condition stream)
             (format stream "Outbox transport failed: ~a"
                     (outbox-transport-error-message condition)))))

(defclass outbox-entry ()
  ((id :initarg :id :reader outbox-entry-id :type string)
   (document-id :initarg :document-id :reader outbox-entry-document-id :type string)
   (dtype :initarg :dtype :reader outbox-entry-dtype :type string)
   (operation :initarg :operation :reader outbox-entry-operation :initform "" :type string)
   (payload :initarg :payload :reader outbox-entry-payload :type string)
   (state :initarg :state :accessor outbox-entry-state :initform :queued)
   (attempts :initarg :attempts :accessor outbox-entry-attempts :initform 0 :type integer)
   (created-at :initarg :created-at :reader outbox-entry-created-at :type integer)
   (updated-at :initarg :updated-at :accessor outbox-entry-updated-at :type integer)
   (next-attempt-at :initarg :next-attempt-at :accessor outbox-entry-next-attempt-at
                    :initform nil)
   (last-error :initarg :last-error :accessor outbox-entry-last-error
               :initform "" :type string)
   (last-status :initarg :last-status :accessor outbox-entry-last-status
                :initform nil)
   (ack-kind :initarg :ack-kind :accessor outbox-entry-ack-kind :initform nil)
   (acknowledged-at :initarg :acknowledged-at :accessor outbox-entry-acknowledged-at
                    :initform nil)))

(conspack:defencoding outbox-entry
  id document-id dtype operation payload state attempts created-at updated-at
  next-attempt-at last-error last-status ack-kind acknowledged-at)

(defun outbox-payload-id (document-id payload)
  "Return a deterministic outbox ID for DOCUMENT-ID and serialized PAYLOAD.

A new StarIntel document version/payload gets a new outbox entry while repeated
enqueue calls for byte-identical payloads collapse to one durable record."
  (starintel:digest-id +outbox-id-version+
                       document-id
                       (starintel:digest-id payload)))

(defun persist-outbox-entry (database entry)
  "Persist ENTRY in DATABASE's named outbox database and return ENTRY."
  (unless (and database (tek9:db-is-open-p database))
    (error "Outbox persistence requires an open operation database."))
  (tek9:put* database entry
             :id (outbox-entry-id entry)
             :database-name +outbox-database-name+)
  entry)

(defun fetch-outbox-entry (database id)
  "Fetch outbox entry ID from DATABASE, or NIL."
  (tek9:fetch* database id :database-name +outbox-database-name+))

(defun list-outbox-entries (database &key state predicate)
  "Return durable outbox entries, optionally filtered by STATE and PREDICATE."
  (unless (and database (tek9:db-is-open-p database))
    (error "Outbox query requires an open operation database."))
  (let (entries)
    (tek9:map-database
     database
     :database-name +outbox-database-name+
     :map-fn
     (lambda (key document)
       (declare (ignore key))
       (let ((entry (tek9:doc-value document)))
         (when (and (typep entry 'outbox-entry)
                    (or (null state) (eq state (outbox-entry-state entry)))
                    (or (null predicate) (funcall predicate entry)))
           (push entry entries)))))
    (sort entries
          (lambda (left right)
            (or (< (outbox-entry-created-at left)
                   (outbox-entry-created-at right))
                (and (= (outbox-entry-created-at left)
                        (outbox-entry-created-at right))
                     (string< (outbox-entry-id left)
                              (outbox-entry-id right))))))))

(defun make-outbox-entry-for-json (json &key operation (now (unix-now)))
  "Construct an outbox entry for canonical StarIntel JSON object JSON."
  (let* ((document-id (jsown:val-safe json "id"))
         (dtype (jsown:val-safe json "dtype"))
         (payload (jsown:to-json json)))
    (unless (and (stringp document-id) (plusp (length document-id)))
      (error "Cannot enqueue StarIntel document without a canonical id."))
    (unless (and (stringp dtype) (plusp (length dtype)))
      (error "Cannot enqueue StarIntel document without dtype."))
    (make-instance 'outbox-entry
                   :id (outbox-payload-id document-id payload)
                   :document-id document-id
                   :dtype dtype
                   :operation (or operation "")
                   :payload payload
                   :created-at now
                   :updated-at now)))

(defun enqueue-starintel-json (database json &key operation (now (unix-now)))
  "Persist JSON in DATABASE before transmission.

Returns ENTRY and true only when this call created a new durable outbox record."
  (let* ((candidate (make-outbox-entry-for-json json :operation operation :now now))
         (existing (fetch-outbox-entry database (outbox-entry-id candidate))))
    (if existing
        (values existing nil)
        (values (persist-outbox-entry database candidate) t))))

(defun enqueue-asset-for-starintel (asset &key (database *db*) (now (unix-now)))
  "Project ASSET to StarIntel JSON and durably enqueue it in DATABASE."
  (let ((json (asset->starintel-json asset)))
    (unless json
      (error "Asset type ~a has no safe StarIntel projection." (asset-kind asset)))
    (enqueue-starintel-json database json
                            :operation (doc-operation asset)
                            :now now)))

(defun outbox-backoff-seconds (attempts
                               &key
                                 (base *outbox-backoff-base-seconds*)
                                 (maximum *outbox-backoff-max-seconds*))
  "Return bounded exponential retry delay for ATTEMPTS."
  (min maximum
       (* base (expt 2 (max 0 (1- attempts))))))

(defun outbox-due-p (entry now)
  "Return true when ENTRY should be attempted at NOW.

SENDING entries are deliberately recoverable: if a process dies after marking
an entry SENDING but before recording the HTTP result, the next drain retries the
same deterministic logical document rather than leaving it stuck forever."
  (case (outbox-entry-state entry)
    ((:queued :sending) t)
    (:retry (let ((next (outbox-entry-next-attempt-at entry)))
              (or (null next) (<= next now))))
    (otherwise nil)))

(defun outbox-retryable-http-status-p (status)
  "Return true when HTTP STATUS should be retried."
  (or (= status 408)
      (= status 425)
      (= status 429)
      (<= 500 status 599)))

(defun outbox-permanent-http-status-p (status)
  "Return true when HTTP STATUS indicates a malformed/unauthorized request.

429 is excluded because rate limiting is transient."
  (and (<= 400 status 499)
       (not (outbox-retryable-http-status-p status))))

(defun mark-outbox-sending (database entry now)
  (incf (outbox-entry-attempts entry))
  (setf (outbox-entry-state entry) :sending
        (outbox-entry-updated-at entry) now
        (outbox-entry-next-attempt-at entry) nil
        (outbox-entry-last-error entry) ""
        (outbox-entry-last-status entry) nil)
  (persist-outbox-entry database entry))

(defun mark-outbox-acknowledged (database entry status now)
  "Record StarIntel HTTP ingest acceptance.

ACK-KIND is :INGEST-ACCEPTED: the server validated and published the document to
its ingest broker. This does not claim that CouchDB persistence has already
completed."
  (setf (outbox-entry-state entry) :acknowledged
        (outbox-entry-updated-at entry) now
        (outbox-entry-next-attempt-at entry) nil
        (outbox-entry-last-error entry) ""
        (outbox-entry-last-status entry) status
        (outbox-entry-ack-kind entry) :ingest-accepted
        (outbox-entry-acknowledged-at entry) now)
  (persist-outbox-entry database entry))

(defun mark-outbox-quarantined (database entry status now)
  (setf (outbox-entry-state entry) :quarantined
        (outbox-entry-updated-at entry) now
        (outbox-entry-next-attempt-at entry) nil
        (outbox-entry-last-status entry) status
        (outbox-entry-last-error entry) (format nil "HTTP ~d rejected document" status))
  (persist-outbox-entry database entry))

(defun mark-outbox-retry-or-failed (database entry message now &optional status)
  (let ((failed-p (>= (outbox-entry-attempts entry) *outbox-max-attempts*)))
    (setf (outbox-entry-state entry) (if failed-p :failed :retry)
          (outbox-entry-updated-at entry) now
          (outbox-entry-last-status entry) status
          (outbox-entry-last-error entry) message
          (outbox-entry-next-attempt-at entry)
          (unless failed-p
            (+ now (outbox-backoff-seconds (outbox-entry-attempts entry)))))
    (persist-outbox-entry database entry)))

(defun process-outbox-entry (database entry transport &key (now (unix-now)))
  "Attempt one ENTRY through TRANSPORT and persist its resulting state.

TRANSPORT is a function of ENTRY returning STATUS and optional response body.
Transport errors should signal OUTBOX-TRANSPORT-ERROR; any unexpected condition
is also converted to a retry/failed state rather than escaping and dropping the
entry."
  (unless (outbox-due-p entry now)
    (return-from process-outbox-entry entry))
  (mark-outbox-sending database entry now)
  (handler-case
      (multiple-value-bind (status body)
          (funcall transport entry)
        (declare (ignore body))
        (cond
          ((and (integerp status) (<= 200 status 299))
           (mark-outbox-acknowledged database entry status now))
          ((and (integerp status) (outbox-permanent-http-status-p status))
           (mark-outbox-quarantined database entry status now))
          (t
           (mark-outbox-retry-or-failed
            database entry
            (if (integerp status)
                (format nil "HTTP ~d did not accept document" status)
                "Transport returned no valid HTTP status")
            now status))))
    (outbox-transport-error (condition)
      (mark-outbox-retry-or-failed
       database entry
       (outbox-transport-error-message condition)
       now))
    (error (condition)
      (mark-outbox-retry-or-failed
       database entry
       (format nil "Transport error: ~a" condition)
       now))))

(defun drain-outbox (database transport &key (now (unix-now)) (limit 100))
  "Process up to LIMIT due outbox entries synchronously in the caller.

Interactive clients should normally use DRAIN-OUTBOX-ASYNC so network work runs
inside the dedicated outbox actor instead of blocking their thread."
  (let ((processed 0)
        results)
    (dolist (entry (list-outbox-entries database) (nreverse results))
      (when (and (< processed limit) (outbox-due-p entry now))
        (incf processed)
        (push (process-outbox-entry database entry transport :now now) results)))))

(defun make-starintel-http-transport (&key
                                       (base-url *starintel-ingest-base-url*)
                                       headers-function
                                       (connect-timeout 5)
                                       (read-timeout 10))
  "Return an HTTP transport for the existing StarIntel single-document ingest API.

HEADERS-FUNCTION is called immediately before each request so credentials do not
need to be persisted in outbox records."
  (let ((root (string-right-trim "/" base-url)))
    (lambda (entry)
      (let* ((url (format nil "~a/new/document/~a"
                          root (outbox-entry-dtype entry)))
             (headers (append
                       '(("Content-Type" . "application/json")
                         ("Accept" . "application/json"))
                       (when headers-function
                         (funcall headers-function)))))
        (handler-case
            (multiple-value-bind (body status)
                (dex:post url
                          :content (outbox-entry-payload entry)
                          :headers headers
                          :connect-timeout connect-timeout
                          :read-timeout read-timeout)
              (values status body))
          (dex:http-request-failed (condition)
            (values (dex:response-status condition)
                    (dex:response-body condition)))
          (error (condition)
            (error 'outbox-transport-error
                   :message (format nil "~a" condition))))))))
