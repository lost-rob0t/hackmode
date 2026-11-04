(defpackage :hackmode-starintel-client-tests
  (:use :cl))

(in-package :hackmode-starintel-client-tests)

;;; Tests for the StarIntel integration surface: configuration, read client,
;;; and durable outbox sync commands. The read client injects a fake request
;;; function so nothing here performs network I/O.

(defun fresh-test-path (name)
  (merge-pathnames
   (format nil "hackmode-starintel-client-~a-~a/" name (tek9:make-key-id))
   (uiop:temporary-directory)))

(defun remove-test-path (path)
  (ignore-errors
   (uiop:delete-directory-tree path :validate t :if-does-not-exist :ignore)))

(defun make-test-config (&key (base-url "http://starintel.example")
                           (api-key "test-api-key")
                           (dataset "star-intel"))
  (make-instance 'hackmode:starintel-config
                 :base-url base-url
                 :api-key api-key
                 :dataset dataset))

(defun run-starintel-config-tests ()
  ;; Explicit values survive construction and readers trim the URL root.
  (let ((config (hackmode:starintel-config-from-env
                 :base-url "https://star.example/"
                 :api-key "secret-key"
                 :dataset "dataset-a")))
    (assert (string= "https://star.example"
                     (hackmode:starintel-config-base-url config)))
    (assert (string= "secret-key"
                     (hackmode:starintel-config-api-key config)))
    (assert (string= "dataset-a"
                     (hackmode:starintel-config-dataset config))))
  ;; Absent or empty environment values fall back to the built-in defaults.
  (let ((hackmode:*starintel-ingest-base-url* "http://127.0.0.1:5000")
        (hackmode:*starintel-dataset* "star-intel"))
    (let ((config (hackmode:starintel-config-from-env
                   :base-url nil :api-key "" :dataset nil)))
      (assert (string= "http://127.0.0.1:5000"
                       (hackmode:starintel-config-base-url config)))
      (assert (string= "" (hackmode:starintel-config-api-key config)))
      (assert (string= "star-intel"
                       (hackmode:starintel-config-dataset config)))))
  ;; Non-HTTP(S) and blank base URLs and datasets are rejected.
  (flet ((expect-config-error (&rest args)
           (let ((signalled nil))
             (handler-case (apply #'hackmode:starintel-config-from-env args)
               (hackmode:starintel-config-error () (setf signalled t)))
             (assert signalled () "expected starintel-config-error"))))
    (expect-config-error :base-url "ftp://star.example" :dataset "d")
    (expect-config-error :base-url "not a url" :dataset "d")
    ;; A blank resolved dataset errors; explicit values are used verbatim.
    (let ((hackmode:*starintel-dataset* ""))
      (expect-config-error :base-url "https://star.example" :dataset nil)))
  ;; Authentication headers derive at call time from the configuration.
  (assert (equal '(("Authorization" . "Bearer secret-key"))
                 (hackmode:starintel-auth-headers
                  (make-test-config :api-key "secret-key"))))
  (assert (null (hackmode:starintel-auth-headers
                 (make-test-config :api-key ""))))
  ;; Reload caches the environment configuration and runs the hook layer.
  (let* ((runs 0)
         (hackmode:*starintel-config* nil)
         (hook (lambda () (incf runs))))
    (unwind-protect
         (progn
           (nhooks:add-hook hackmode:*starintel-config-hook* hook)
           (let ((config (hackmode:reload-starintel-config)))
             (assert (eq config hackmode:*starintel-config*))
             (assert (= 1 runs))
             (assert (eq config (hackmode:current-starintel-config)))
             (assert (= 1 runs))))
      (nhooks:remove-hook hackmode:*starintel-config-hook* hook)
      (setf hackmode:*starintel-config* nil)))
  ;; Configuration printing never leaks the API key value.
  (let ((printed
          (with-output-to-string (stream)
            (print (make-test-config :api-key "leak-me-please") stream))))
    (assert (search "masked" printed))
    (assert (not (search "leak-me-please" printed))))
  t)

;;; Read client: the transport is always an injected fake.

(defun fake-request (body status)
  "Return a request function answering BODY and STATUS for every call."
  (lambda (url &key headers connect-timeout read-timeout)
    (declare (ignore url headers connect-timeout read-timeout))
    (values body status)))

(defun run-starintel-client-tests ()
  (let ((client (hackmode:make-starintel-client
                 :config (make-test-config)
                 :request-fn (fake-request "{\"ok\":true}" 200))))
    ;; URL construction: root trimmed, paths joined, params encoded.
    (assert (string= "http://starintel.example/document/abc"
                     (hackmode:starintel-client-url client "/document/abc")))
    (assert (string= "http://starintel.example/search?q=a%20b&limit=10"
                     (hackmode:starintel-client-url
                      client "/search"
                      :query-params '(("q" . "a b") ("limit" . "10")))))
    ;; Successful document fetch parses JSON.
    (let ((document (hackmode:starintel-get-document client "abc")))
      (assert (eq t (jsown:val-safe document "ok"))))
    ;; Health probe follows the status code.
    (assert (hackmode:starintel-health-p client)))
  ;; Error statuses map into the keyword result space; malformed bodies are
  ;; reported as :BAD-RESPONSE rather than raising.
  (flet ((client-returning (body status)
           (hackmode:make-starintel-client
            :config (make-test-config)
            :request-fn (fake-request body status))))
    (assert (eq :not-found
                (hackmode:starintel-get-document
                 (client-returning "{}" 404) "abc")))
    (assert (eq :unauthorized
                (hackmode:starintel-get-document
                 (client-returning "{}" 401) "abc")))
    (assert (eq :server-error
                (hackmode:starintel-get-document
                 (client-returning "{}" 503) "abc")))
    (assert (eq :client-error
                (hackmode:starintel-get-document
                 (client-returning "{}" 418) "abc")))
    (assert (eq :bad-response
                (hackmode:starintel-get-document
                 (client-returning "not json" 200) "abc")))
    ;; Transport failures surface as :UNREACHABLE, not conditions.
    (let ((unreachable
            (hackmode:make-starintel-client
             :config (make-test-config)
             :request-fn (lambda (url &key headers connect-timeout read-timeout)
                           (declare (ignore url headers connect-timeout
                                            read-timeout))
                           (error "connection refused")))))
      (assert (eq :unreachable
                  (hackmode:starintel-get-document unreachable "abc")))))
  ;; Search parses the envelope: rows, embedded docs, and the next bookmark.
  (let* ((body "{\"rows\":[{\"doc\":{\"_id\":\"doc-one\"}},
                          {\"doc\":{\"_id\":\"doc-two\"}}],
                  \"bookmark\":\"next-page\"}")
         (client (hackmode:make-starintel-client
                  :config (make-test-config)
                  :request-fn (fake-request body 200))))
    (multiple-value-bind (documents bookmark)
        (hackmode:starintel-search client "query" :limit 2)
      (assert (= 2 (length documents)))
      (assert (string= "doc-one"
                       (jsown:val-safe (first documents) "_id")))
      (assert (string= "next-page" bookmark))))
  ;; A failing search returns the keyword result with no bookmark.
  (let ((client (hackmode:make-starintel-client
                 :config (make-test-config)
                 :request-fn (fake-request "{}" 403))))
    (multiple-value-bind (documents bookmark)
        (hackmode:starintel-search client "query")
      (assert (eq :unauthorized documents))
      (assert (null bookmark))))
  t)

;;; Outbox sync commands over a real (temporary) operation database.

(defun make-domain-asset (name)
  (make-instance 'hackmode:domain
                 :record name
                 :record-type "A"
                 :operation "starintel-client-test"
                 :date-added 1000
                 :date-updated 1000))

(defun run-starintel-outbox-command-tests ()
  (let* ((root (fresh-test-path "outbox-sync"))
         (db (tek9:new-database "operation" :path root))
         (config (make-test-config)))
    (unwind-protect
         (progn
           (tek9:open-database db)
           ;; Empty outbox: nothing due, nothing remaining.
           (let ((report (hackmode:starintel-sync :database db :config config)))
             (assert (zerop (getf report :acked)))
             (assert (zerop (getf report :remaining))))
           ;; A failing transport keeps entries awaiting retry and the
           ;; remaining count reflects the durable state.
           (hackmode:enqueue-asset-for-starintel
            (make-domain-asset "retry.example") :database db :now 1000)
           (let ((report
                   (hackmode:starintel-sync
                    :database db :config config
                    :now 1000
                    :transport (lambda (entry)
                                 (declare (ignore entry))
                                 (values 503 "unavailable")))))
             (assert (zerop (getf report :acked)))
             (assert (plusp (getf report :retried)))
             (assert (= 1 (getf report :remaining))))
           ;; An accepting transport acknowledges the entry.
           (let ((report
                   (hackmode:starintel-sync
                    :database db :config config
                    :now 2000
                    :transport (lambda (entry)
                                 (declare (ignore entry))
                                 (values 202 "accepted")))))
             (assert (= 1 (getf report :acked)))
             (assert (zerop (getf report :remaining))))
           ;; State counts and filtered listing agree with the store.
           (multiple-value-bind (counts entries)
               (hackmode:starintel-outbox-status
                :database db :state :acknowledged)
             (assert (= 1 (getf counts :total)))
             (assert (= 1 (getf counts :acknowledged)))
             (assert (= 1 (length entries))))
           ;; The config-derived transport is a funcallable transport for
           ;; STARINTEL-SYNC; credential headers derive from the live
           ;; configuration at send time (STARINTEL-AUTH-HEADERS above).
           (let ((transport (hackmode:starintel-sync-transport config)))
             (assert (functionp transport)))
           ;; Printing the report returns it unchanged.
           (let ((report (hackmode:starintel-sync :database db :config config)))
             (assert (eq report
                         (hackmode:print-starintel-sync-report report)))))
      (when (tek9:db-is-open-p db)
        (tek9:close-database db))
      (remove-test-path root)))
  t)

(defun run-starintel-client-all-tests ()
  (run-starintel-config-tests)
  (run-starintel-client-tests)
  (run-starintel-outbox-command-tests)
  t)
