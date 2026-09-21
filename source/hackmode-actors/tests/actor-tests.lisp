(in-package :hackmode-actors-tests)

(defun fresh-test-path (prefix)
  (merge-pathnames
   (format nil "~a-~a/" prefix (tek9:make-key-id))
   (uiop:temporary-directory)))

(defun remove-test-path (path)
  (ignore-errors
    (uiop:delete-directory-tree path :validate t :if-does-not-exist :ignore)))

(defun run-actor-spawn-test ()
  (hackmode-actors:stop-hackmode-ontology-actors)
  (let ((actors (hackmode-actors:ensure-hackmode-ontology-actors)))
    (unwind-protect
         (progn
           (assert (= 6 (length actors)) ()
                   "expected six ontology actors, got ~a" (length actors))
           (dolist (name '("asset-monitor" "outbox" "provider-dispatcher"
                           "capture-supervisor" "replay" "expert-advisor"))
             (assert (hackmode-actors:hackmode-ontology-actor name) ()
                     "actor ~a should be live" name))
           (assert (hackmode-actors:hackmode-ontology-actor :outbox)
                   ()
                   "actor lookup accepts keywords"))
      (hackmode-actors:stop-hackmode-ontology-actors))
    (assert (null hackmode-actors:*ontology-actors*) ()
            "actor registry must be empty after stop")))

(defun run-actor-message-round-trip-test ()
  ;; Invalid messages must be rejected by the actor boundary.
  (hackmode-actors:stop-hackmode-ontology-actors)
  (hackmode-actors:ensure-hackmode-ontology-actors)
  (let ((root (fresh-test-path "hm-actors-db"))
        (previous-db hackmode:*db*))
    (unwind-protect
         (let ((db (tek9:new-database "actor-test" :path root)))
           ;; Actors run on their own threads; the database must be globally
           ;; visible, not just dynamically bound in the test thread.
           (tek9:open-database db)
           (setf hackmode:*db* db)
           (unwind-protect
                (progn
                  ;; asset-monitor answers negatively for unknown assets.
                  (let ((reply
                          (hackmode-actors:ask-hackmode-actor
                           :asset-monitor
                           (hackmode-actors:make-ontology-wire-message
                            "hackmode/asset-discovered@1"
                            '(("assetId" . "does-not-exist")
                              ("kind" . "domain")))
                           :timeout 5)))
                    (assert (member '(:ok . nil) reply :test #'equal) ()
                            "expected negative reply, got ~s" reply))
                  ;; enqueue-document durably persists the projected payload.
                  (hackmode-actors:ask-hackmode-actor
                   :outbox
                   (hackmode-actors:make-ontology-wire-message
                    "hackmode/enqueue-document@1"
                    `(("json" . ,(hackmode-actors:operation->starintel-json
                                  (make-instance 'hackmode:operation
                                                 :name "round-trip"
                                                 :dir "/tmp/round-trip/")))
                      ("dtype" . "operation")))
                   :timeout 5)
                  (assert (= 1 (length (hackmode:list-outbox-entries
                                        hackmode:*db*)))
                          ()
                          "enqueued document should be durable"))
             (progn
               (setf hackmode:*db* previous-db)
               (ignore-errors (tek9:close-database db)))))
      (remove-test-path root)
      (hackmode-actors:stop-hackmode-ontology-actors))))

(defun run-actor-invalid-message-test ()
  ;; The receive handler validates against the compiled ontology; an invalid
  ;; payload surfaces as a sento ask failure without crashing the actor.
  (hackmode-actors:stop-hackmode-ontology-actors)
  (hackmode-actors:ensure-hackmode-ontology-actors)
  (unwind-protect
       (assert
        (signals-condition-p
         'starsentocompat:sento-ask-failure-error
         (lambda ()
           (hackmode-actors:ask-hackmode-actor
            :expert-advisor
            (hackmode-actors:make-ontology-wire-message
             "hackmode/recommend-capabilities@1"
             '(("target" . 42)))
            :timeout 5))))
    (hackmode-actors:stop-hackmode-ontology-actors)))

(defun run-actor-tests ()
  (run-actor-spawn-test)
  (run-actor-message-round-trip-test)
  (run-actor-invalid-message-test))

(defun run-all-tests ()
  (run-ontology-tests)
  (run-projection-tests)
  (run-actor-tests)
  (format t "~&hackmode-actors tests passed~%"))
