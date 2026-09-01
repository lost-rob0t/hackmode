(in-package :hackmode)

(defstruct ipx-replay-result
  operation-id
  capture-session-id
  source-id
  (start-offset 0 :type integer)
  (end-offset 0 :type integer)
  (committed-count 0 :type integer)
  (quarantine-count 0 :type integer)
  (truncated-p nil :type boolean))

(defun ipx-require-string (value label)
  (unless (and (stringp value) (plusp (length value)))
    (error "~a must be a non-empty string." label))
  value)

(defun ipx-json-value (object key)
  (or (jsown:val-safe object key)
      (error "Missing IPX field ~a." key)))

(defun ipx-require-real (value label)
  (unless (realp value)
    (error "~a must be a real number." label))
  value)

(defun ipx-octets->ascii (octets)
  (map 'string #'code-char octets))

(defun ipx-read-frame (stream)
  "Read one newline-delimited frame and return OCTETS, COMPLETE-P, START, END."
  (let ((start (file-position stream))
        (octets (make-array 256
                            :element-type '(unsigned-byte 8)
                            :adjustable t
                            :fill-pointer 0)))
    (loop
      for octet = (read-byte stream nil :eof)
      do (cond
           ((eq octet :eof)
            (return (values octets nil start (file-position stream))))
           ((= octet 10)
            (return (values octets t start (file-position stream))))
           (t
            (vector-push-extend octet octets))))))

(defun ipx-evidence-reference (pathname source-id start end)
  (format nil "ipx://~a?path=~a#bytes=~d-~d"
          source-id (namestring pathname) start end))

(defun ipx-frame-provenance (pathname source-id start end)
  (list :parser "hackmode-ipx-http/1"
        :source-id source-id
        :source-path (namestring pathname)
        :offset start
        :length (- end start)))

(defun ipx-quarantine-at-offset-p
    (database operation-id capture-session-id source-id offset)
  (find offset
        (hackmode-database:fetch-capture-quarantine-records
         database operation-id capture-session-id source-id)
        :key (lambda (record)
               (getf (hackmode-database:execution-record-payload record) :offset))
        :test #'=))

(defun ipx-persist-quarantine
    (database pathname operation-id capture-session-id source-id start end reason)
  (unless (ipx-quarantine-at-offset-p
           database operation-id capture-session-id source-id start)
    (let ((record
            (hackmode-database:make-capture-quarantine-record
             :operation-id operation-id
             :capture-session-id capture-session-id
             :source-id source-id
             :offset start
             :length (- end start)
             :reason reason
             :raw-evidence-ref
             (ipx-evidence-reference pathname source-id start end)
             :framing-version "hackmode-ipx-http/1"
             :provenance
             (ipx-frame-provenance pathname source-id start end))))
      (hackmode-database:persist-execution-record database record)
      record)))

(defun ipx-validate-identity
    (object operation-id capture-session-id source-id)
  (unless (string= "hackmode-ipx-http" (ipx-json-value object "schema"))
    (error "Unsupported IPX schema."))
  (unless (= 1 (ipx-json-value object "version"))
    (error "Unsupported IPX version."))
  (unless (string= operation-id (ipx-json-value object "operation_id"))
    (error "IPX operation identity mismatch."))
  (unless (string= capture-session-id
                   (ipx-json-value object "capture_session_id"))
    (error "IPX capture-session identity mismatch."))
  (unless (string= source-id (ipx-json-value object "spool_id"))
    (error "IPX source identity mismatch."))
  object)

(defun ipx-object->http-exchange
    (object pathname operation-id capture-session-id source-id start end)
  (ipx-validate-identity object operation-id capture-session-id source-id)
  (let* ((request (ipx-json-value object "request"))
         (response (ipx-json-value object "response"))
         (timestamp-start
           (ipx-require-real (ipx-json-value object "timestamp_start")
                             "timestamp_start"))
         (timestamp-end
           (ipx-require-real (ipx-json-value object "timestamp_end")
                             "timestamp_end")))
    (when (< timestamp-end timestamp-start)
      (error "IPX timestamp_end precedes timestamp_start."))
    (hackmode-database:make-http-exchange-record
     :operation-id operation-id
     :capture-session-id capture-session-id
     :exchange-id (ipx-json-value object "exchange_id")
     :method (ipx-json-value request "method")
     :scheme (ipx-json-value request "scheme")
     :host (ipx-json-value request "host")
     :port (ipx-json-value request "port")
     :path (ipx-json-value request "path")
     :response-status (ipx-json-value response "status_code")
     :raw-evidence-ref (ipx-evidence-reference pathname source-id start end)
     :observed-at (unix-seconds->starintel-timestring (floor timestamp-start))
     :duration-ms (round (* 1000 (- timestamp-end timestamp-start)))
     :provenance (ipx-frame-provenance pathname source-id start end))))

(defun ipx-persist-checkpoint
    (database operation-id capture-session-id source-id offset last-record-id pathname)
  (hackmode-database:persist-execution-record
   database
   (hackmode-database:make-capture-checkpoint-record
    :operation-id operation-id
    :capture-session-id capture-session-id
    :source-id source-id
    :offset offset
    :last-record-id last-record-id
    :framing-version "hackmode-ipx-http/1"
    :provenance (list :parser "hackmode-ipx-http/1"
                      :source-id source-id
                      :source-path (namestring pathname)))))

(defun replay-ipx-http-spool
    (database pathname &key operation-id capture-session-id source-id)
  "Replay complete HTTP frames from PATHNAME into the canonical operation graph.

Checkpoint offsets are byte offsets. Complete malformed frames are quarantined and
advanced past. An unterminated final frame is quarantined without advancing the
checkpoint so a later replay can consume it after the writer completes the frame."
  (ipx-require-string operation-id "operation-id")
  (ipx-require-string capture-session-id "capture-session-id")
  (ipx-require-string source-id "source-id")
  (let* ((path (pathname pathname))
         (checkpoint
           (hackmode-database:fetch-latest-capture-checkpoint
            database operation-id capture-session-id source-id))
         (start-offset
           (if checkpoint
               (getf (hackmode-database:execution-record-payload checkpoint)
                     :offset)
               0))
         (committed-count 0)
         (quarantine-count 0)
         (truncated-p nil)
         (end-offset start-offset))
    (with-open-file (stream path
                            :direction :input
                            :element-type '(unsigned-byte 8))
      (file-position stream start-offset)
      (loop
        (multiple-value-bind (octets complete-p frame-start frame-end)
            (ipx-read-frame stream)
          (setf end-offset frame-end)
          (when (and (zerop (length octets)) (not complete-p))
            (return))
          (unless complete-p
            (setf truncated-p t)
            (when (ipx-persist-quarantine
                   database path operation-id capture-session-id source-id
                   frame-start frame-end "truncated IPX frame")
              (incf quarantine-count))
            (return))
          (handler-case
              (let* ((object (jsown:parse (ipx-octets->ascii octets)))
                     (exchange
                       (ipx-object->http-exchange
                        object path operation-id capture-session-id source-id
                        frame-start frame-end)))
                (hackmode-database:persist-execution-record database exchange)
                (ipx-persist-checkpoint
                 database operation-id capture-session-id source-id frame-end
                 (hackmode-database:execution-record-record-id exchange) path)
                (incf committed-count))
            (error (condition)
              (let ((quarantine
                      (ipx-persist-quarantine
                       database path operation-id capture-session-id source-id
                       frame-start frame-end (princ-to-string condition))))
                (when quarantine
                  (incf quarantine-count))
                (ipx-persist-checkpoint
                 database operation-id capture-session-id source-id frame-end
                 (and quarantine
                      (hackmode-database:execution-record-record-id quarantine))
                 path)))))))
    (make-ipx-replay-result
     :operation-id operation-id
     :capture-session-id capture-session-id
     :source-id source-id
     :start-offset start-offset
     :end-offset end-offset
     :committed-count committed-count
     :quarantine-count quarantine-count
     :truncated-p truncated-p)))
