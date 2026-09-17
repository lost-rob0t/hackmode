(defpackage :hackmode-tool-actor-tests
  (:use :cl))

(in-package :hackmode-tool-actor-tests)

(defun check (condition control &rest arguments)
  (unless condition
    (error (apply #'format nil control arguments))))

(defun fresh-path (prefix)
  (merge-pathnames
   (format nil "~a-~a/" prefix (tek9:make-key-id))
   (uiop:temporary-directory)))

(defun remove-path (path)
  (ignore-errors
    (uiop:delete-directory-tree
     path :validate t :if-does-not-exist :ignore)))

(defun with-open-test-databases (function)
  (let* ((journal-path (fresh-path "hackmode-tool-journal"))
         (operation-path (fresh-path "hackmode-tool-operation"))
         (journal-db (tek9:new-database "operations" :path journal-path))
         (operation-db (tek9:new-database "operation" :path operation-path)))
    (unwind-protect
         (progn
           (tek9:open-database journal-db)
           (tek9:open-database operation-db)
           (funcall function journal-db operation-db))
      (when (tek9:db-is-open-p journal-db)
        (tek9:close-database journal-db))
      (when (tek9:db-is-open-p operation-db)
        (tek9:close-database operation-db))
      (remove-path journal-path)
      (remove-path operation-path))))

(defun run-target-shape-tests ()
  (let ((domain (hackmode:find-tool-target-shape 'domain))
        (url (hackmode:find-tool-target-shape 'url))
        (network (hackmode:find-tool-target-shape 'network)))
    (check domain "Domain target shape was not registered.")
    (check (hackmode:tool-target-shape-accepts-p domain "example.org")
           "Domain target shape rejected a valid domain.")
    (check (not (hackmode:tool-target-shape-accepts-p domain "https://example.org/"))
           "Domain target shape accepted a URL.")
    (check (hackmode:tool-target-shape-accepts-p url "https://example.org/")
           "URL target shape rejected HTTPS.")
    (check (hackmode:tool-target-shape-accepts-p network "192.0.2.0/24")
           "Network target shape rejected CIDR input.")))

(defun run-false-option-preservation-test ()
  (let* ((mapping
           (hackmode:register-tool-mapping
            :test-options :test-options
            :target-shapes '(raw)
            :arguments
            (list
             (hackmode:make-tool-arg
              :enabled 'boolean :default t :flag "--enabled"))))
         (input
           (hackmode:make-validated-tool-command-input
            mapping
            "target"
            :arguments '(:enabled nil))))
    (check (hackmode::plist-key-present-p
            (hackmode:tool-command-input-arguments input)
            :enabled)
           "Explicit NIL boolean argument was mistaken for a missing key.")
    (check (null (getf (hackmode:tool-command-input-arguments input) :enabled))
           "Explicit NIL boolean argument was overwritten by its default.")))

(defun run-kali-catalog-tests ()
  (dolist (identity '((:network-scan :nmap)
                      (:subdomain-enumerate :subfinder)
                      (:vulnerability-scan :nuclei)
                      (:content-discovery :ffuf)
                      (:sql-assessment :sqlmap)))
    (destructuring-bind (capability provider) identity
      (let ((mapping (hackmode:find-tool-mapping capability provider)))
        (check mapping "Missing Kali mapping ~a/~a." capability provider)
        (check (member "kali" (hackmode:tool-mapping-platforms mapping)
                       :test #'string=)
               "Kali is not a declared platform for ~a/~a."
               capability provider)
        (check (hackmode:find-capability-provider capability provider)
               "Kali mapping ~a/~a has no executable provider actor backend."
               capability provider))))
  (let ((ffuf (hackmode:find-tool-mapping :content-discovery :ffuf)))
    (check (find :wordlist
                 (hackmode:tool-mapping-arguments ffuf)
                 :key #'hackmode:tool-argument-name)
           "FFUF mapping lost its typed wordlist argument.")))

(defun run-journal-tests ()
  (with-open-test-databases
   (lambda (journal-db operation-db)
     (declare (ignore operation-db))
     (let ((hackmode:*operations-database* journal-db)
           (sink-calls 0)
           (hackmode:*actor-event-sink*
             (lambda (event)
               (declare (ignore event))
               (incf sink-calls)
               (error "projection intentionally unavailable"))))
       (multiple-value-bind (first status)
           (hackmode:append-hackmode-actor-event
            "actor/test"
            :defined
            '(:name "test")
            :event-id "tool-event-1")
         (check (eq :appended status) "First journal append did not commit.")
         (check (= 0 (getf first :sequence))
                "First actor event did not receive sequence zero."))
       (check (= 1 sink-calls)
              "Projection sink was not attempted after canonical append.")
       (multiple-value-bind (replayed status)
           (hackmode:append-hackmode-actor-event
            "actor/test"
            :defined
            '(:name "test")
            :event-id "tool-event-1")
         (check (eq :replayed status) "Identical actor event was not replay-safe.")
         (check (= 0 (getf replayed :sequence))
                "Replayed actor event lost its original sequence."))
       (check (= 1 sink-calls)
              "Replayed canonical events must not re-run projection side effects.")
       (hackmode:append-hackmode-actor-event
        "actor/test"
        :ready
        '(:state :online)
        :event-id "tool-event-2")
       (let ((events (hackmode:replay-hackmode-actor-events "actor/test")))
         (check (= 2 (length events)) "Actor event replay lost committed events.")
         (check (equal '(0 1) (mapcar (lambda (event) (getf event :sequence)) events))
                "Actor event replay is not sequence ordered."))
       (handler-case
           (progn
             (hackmode:append-hackmode-actor-event
              "actor/test"
              :defined
              '(:name "different")
              :event-id "tool-event-1")
             (error "Conflicting immutable actor event was accepted."))
         (hackmode:hackmode-actor-event-conflict () t))))))

(defun run-tool-idempotency-test ()
  (with-open-test-databases
   (lambda (journal-db operation-db)
     (let ((hackmode:*operations-database* journal-db)
           (hackmode:*db* operation-db)
           (calls 0))
       (hackmode:register-tool-mapping
        :test-replay :test-replay
        :target-shapes '(raw)
        :example-targets '("alpha"))
       (hackmode:register-capability-provider
        :test-replay
        :test-replay
        (lambda (target)
          (incf calls)
          (list
           (make-instance
            'hackmode:finding
            :document-id target
            :finding-type "test-result"
            :data (format nil "call-~d" calls)
            :tool "test-replay")))
        :input-type 'string
        :output-types '(hackmode:finding)
        :priority 1)
       (unwind-protect
            (let* ((definition
                     (hackmode:find-capability-provider
                      :test-replay :test-replay))
                   (first
                     (hackmode::execute-tool-actor-request
                      definition "alpha" :database operation-db))
                   (second
                     (hackmode::execute-tool-actor-request
                      definition "alpha" :database operation-db))
                   (third
                     (hackmode::execute-tool-actor-request
                      definition "alpha"
                      :idempotency-key "fresh-run"
                      :database operation-db)))
              (check (= 2 calls)
                     "Deterministic replay reran a completed external tool command.")
              (check (equal first second)
                     "Repeated tool command did not replay the same terminal result.")
              (check (not (string= (getf first :command-id)
                                   (getf third :command-id)))
                     "Explicit idempotency key did not create a distinct command identity."))
         (hackmode:unregister-capability-provider
          :test-replay :test-replay))))))

(defun run-tool-actor-and-manifest-tests ()
  (with-open-test-databases
   (lambda (journal-db operation-db)
     (declare (ignore operation-db))
     (let ((hackmode:*operations-database* journal-db))
       (unwind-protect
            (progn
              (hackmode:start-hackmode-actor)
              (let ((descriptors (hackmode:list-tool-actor-descriptors)))
                (check descriptors "Dynamic tool actor catalog is empty.")
                (check
                 (find "hackmode.tool.network-scan.nmap"
                       descriptors
                       :test #'string=
                       :key (lambda (descriptor) (getf descriptor :name)))
                 "Nmap tool actor is not visible from Hackmode."))
              (let* ((manifest (hackmode:hackmode-actor-manifest))
                     (json (hackmode:encode-hackmode-actor-manifest manifest)))
                (check (plusp (length (getf manifest :resources)))
                       "Registry manifest contains no actor resources.")
                (check (search "star://" json)
                       "Registry manifest omitted canonical STAR actor URIs.")
                (check (search "targetShapes" json)
                       "Registry manifest omitted target-shape metadata.")
                (check (null (search "executable" json))
                       "Registry manifest leaked process-local executable metadata.")))
         (hackmode:stop-hackmode-actor-system))))))

(defun run-tool-actor-tests ()
  (run-target-shape-tests)
  (run-false-option-preservation-test)
  (run-kali-catalog-tests)
  (run-journal-tests)
  (run-tool-idempotency-test)
  (run-tool-actor-and-manifest-tests)
  t)
