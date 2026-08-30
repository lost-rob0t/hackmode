(in-package :hackmode-database-tests)

(defun run-replay-conflict-tests ()
  (let* ((path (merge-pathnames
                (format nil "hackmode-replay-~D/" (random 1000000000))
                (uiop:temporary-directory)))
         (database (tek9:new-database "hackmode-replay-test" :path path)))
    (unwind-protect
         (progn
           (tek9:open-database database)
           (let* ((graph "hackmode/replay-test")
                  (first (make-instance 'tek9:node
                                        :id "node-1"
                                        :props '(:kind :evidence
                                                 :payload (:value 1))))
                  (same (make-instance 'tek9:node
                                       :id "node-1"
                                       :props '(:kind :evidence
                                                :payload (:value 1))))
                  (conflict (make-instance 'tek9:node
                                           :id "node-1"
                                           :props '(:kind :evidence
                                                    :payload (:value 2)))))
             (ensure (eq :inserted
                         (persist-graph-node-replay-safe database first
                                                        :database-name graph))
                     "first replay-safe node write was not inserted")
             (ensure (eq :replayed
                         (persist-graph-node-replay-safe database same
                                                        :database-name graph))
                     "identical node replay was not idempotent")
             (ensure (equal '(:kind :evidence :payload (:value 1))
                            (tek9:node-props
                             (tek9:fetch-node database "node-1"
                                              :database-name graph)))
                     "identical replay changed canonical node content")
             (handler-case
                 (progn
                   (persist-graph-node-replay-safe database conflict
                                                   :database-name graph)
                   (error "same-ID/different-content node replay unexpectedly overwrote canonical evidence"))
               (persistence-replay-conflict (condition)
                 (ensure (string= "node-1"
                                  (persistence-replay-conflict-record-id condition))
                         "node conflict lost record identity")))
             (ensure (equal '(:kind :evidence :payload (:value 1))
                            (tek9:node-props
                             (tek9:fetch-node database "node-1"
                                              :database-name graph)))
                     "conflicting replay modified canonical node content")
             (let* ((edge (make-instance 'tek9:edge
                                         :id "edge-1"
                                         :source "node-1"
                                         :predicate :derived-from
                                         :target "node-2"))
                    (same-edge (make-instance 'tek9:edge
                                              :id "edge-1"
                                              :source "node-1"
                                              :predicate :derived-from
                                              :target "node-2"))
                    (conflict-edge (make-instance 'tek9:edge
                                                  :id "edge-1"
                                                  :source "node-1"
                                                  :predicate :derived-from
                                                  :target "node-3")))
               (persist-graph-node-replay-safe
                database
                (make-instance 'tek9:node :id "node-2" :props '(:kind :target))
                :database-name graph)
               (persist-graph-node-replay-safe
                database
                (make-instance 'tek9:node :id "node-3" :props '(:kind :target))
                :database-name graph)
               (ensure (eq :inserted
                           (persist-graph-edge-replay-safe database edge
                                                          :database-name graph))
                       "first replay-safe edge write was not inserted")
               (ensure (eq :replayed
                           (persist-graph-edge-replay-safe database same-edge
                                                          :database-name graph))
                       "identical edge replay was not idempotent")
               (handler-case
                   (progn
                     (persist-graph-edge-replay-safe database conflict-edge
                                                     :database-name graph)
                     (error "same-ID/different-content edge replay unexpectedly overwrote canonical evidence"))
                 (persistence-replay-conflict () t)))))
      (when (tek9:db-is-open-p database)
        (tek9:close-database database))
      (when (probe-file path)
        (uiop:delete-directory-tree path :validate t))))
  t)
