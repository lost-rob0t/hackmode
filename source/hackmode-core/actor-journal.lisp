(in-package :hackmode)

(defparameter +actor-event-records-db+ "actor-events")
(defparameter +actor-event-stream-db+ "actor-event-stream")
(defparameter +actor-event-heads-db+ "actor-event-heads")

(define-condition hackmode-actor-event-conflict (error)
  ((event-id :initarg :event-id :reader hackmode-actor-event-conflict-event-id)
   (existing :initarg :existing :reader hackmode-actor-event-conflict-existing)
   (incoming :initarg :incoming :reader hackmode-actor-event-conflict-incoming))
  (:report
   (lambda (condition stream)
     (format stream "Actor event id ~a names conflicting immutable content."
             (hackmode-actor-event-conflict-event-id condition)))))

(defvar *actor-event-sink* nil
  "Optional function receiving each newly appended Hackmode actor event.")

(defun actor-event-stream-key (stream-id sequence)
  (format nil "~8,'0X:~A:~20,'0D"
          (length (babel:string-to-octets stream-id :encoding :utf-8))
          stream-id
          sequence))

(defun actor-event-payload-digest (payload)
  (starintel:digest-id
   "hackmode-actor-event-payload-v1"
   (with-standard-io-syntax
     (let ((*print-readably* t)
           (*print-pretty* nil)
           (*print-circle* nil))
       (prin1-to-string payload)))))

(defun ensure-actor-event-databases (&optional (database *operations-database*))
  (unless (and database (tek9:db-is-open-p database))
    (setf database (ensure-operations-database-open)))
  (dolist (name (list +actor-event-records-db+
                      +actor-event-stream-db+
                      +actor-event-heads-db+))
    (tek9:database-db database name
                      :key-encoding :utf-8
                      :value-encoding :octets))
  database)

(defun same-hackmode-actor-event-p (event stream-id event-type payload digest)
  (and (string= (getf event :stream-id) stream-id)
       (eq (getf event :event-type) event-type)
       (string= (getf event :payload-digest) digest)
       (equal (getf event :payload) payload)))

(defun append-hackmode-actor-event (stream-id event-type payload
                                    &key event-id
                                      (timestamp (unix-now))
                                      (database *operations-database*))
  "Atomically append one immutable product-runtime event.

EVENT-ID makes retries idempotent. The event body, ordered stream row and stream
head commit in one Tek9 transaction. Reusing an id with different content fails
closed."
  (unless (and (stringp stream-id) (plusp (length stream-id)))
    (error "Actor event stream id must be a non-empty string."))
  (unless (keywordp event-type)
    (error "Actor event type must be a keyword, got ~s." event-type))
  (let* ((database (ensure-actor-event-databases database))
         (owned-payload (copy-tree payload))
         (digest (actor-event-payload-digest owned-payload))
         (stable-id
           (or event-id
               (starintel:digest-id
                "hackmode-actor-event-v1"
                stream-id
                (string-downcase (symbol-name event-type))
                digest))))
    (tek9:with-write-transaction
        (database :database-names
                  '("actor-events" "actor-event-stream" "actor-event-heads"))
      (let ((existing
              (tek9:fetch* database stable-id
                           :database-name +actor-event-records-db+)))
        (when existing
          (if (same-hackmode-actor-event-p
               existing stream-id event-type owned-payload digest)
              (return-from append-hackmode-actor-event
                (values (copy-tree existing) :replayed))
              (error 'hackmode-actor-event-conflict
                     :event-id stable-id
                     :existing (copy-tree existing)
                     :incoming (list :stream-id stream-id
                                     :event-type event-type
                                     :payload owned-payload
                                     :payload-digest digest))))
        (let* ((head
                 (tek9:fetch* database stream-id
                              :database-name +actor-event-heads-db+))
               (sequence (if head (1+ (getf head :sequence)) 0))
               (predecessor (and head (getf head :event-id)))
               (event
                 (list :event-id stable-id
                       :stream-id stream-id
                       :sequence sequence
                       :predecessor-id predecessor
                       :event-type event-type
                       :payload owned-payload
                       :payload-digest digest
                       :timestamp timestamp)))
          (tek9:put* database event
                     :id stable-id
                     :database-name +actor-event-records-db+)
          (tek9:put* database stable-id
                     :id (actor-event-stream-key stream-id sequence)
                     :database-name +actor-event-stream-db+)
          (tek9:put* database
                     (list :sequence sequence
                           :event-id stable-id
                           :payload-digest digest)
                     :id stream-id
                     :database-name +actor-event-heads-db+)
          (when *actor-event-sink*
            (funcall *actor-event-sink* (copy-tree event)))
          (values event :appended))))))

(defun replay-hackmode-actor-events (stream-id
                                     &key (database *operations-database*))
  "Return STREAM-ID actor events in sequence order, failing on gaps."
  (let* ((database (ensure-actor-event-databases database))
         (head
           (tek9:fetch* database stream-id
                        :database-name +actor-event-heads-db+)))
    (unless head
      (return-from replay-hackmode-actor-events nil))
    (let* ((last-sequence (getf head :sequence))
           (rows
             (tek9:select-primary-range
              database
              (actor-event-stream-key stream-id 0)
              :end (actor-event-stream-key stream-id last-sequence)
              :database-name +actor-event-stream-db+))
           (expected 0)
           (previous nil)
           events)
      (dolist (row rows)
        (let* ((event-id (cdr row))
               (event
                 (and event-id
                      (tek9:fetch* database event-id
                                   :database-name +actor-event-records-db+))))
          (unless event
            (error "Missing actor event body at ~a sequence ~d."
                   stream-id expected))
          (unless (= expected (getf event :sequence))
            (error "Actor event stream ~a jumped from ~d to ~d."
                   stream-id expected (getf event :sequence)))
          (unless (equal previous (getf event :predecessor-id))
            (error "Actor event stream ~a predecessor mismatch at sequence ~d."
                   stream-id expected))
          (push (copy-tree event) events)
          (setf previous (getf event :event-id))
          (incf expected)))
      (unless (= expected (1+ last-sequence))
        (error "Actor event stream ~a is incomplete at sequence ~d."
               stream-id expected))
      (nreverse events))))
