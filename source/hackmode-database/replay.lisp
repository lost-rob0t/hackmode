(in-package :hackmode-database)

(define-condition persistence-replay-conflict (error)
  ((record-kind :initarg :record-kind :reader persistence-replay-conflict-record-kind)
   (record-id :initarg :record-id :reader persistence-replay-conflict-record-id)
   (database-name :initarg :database-name
                  :reader persistence-replay-conflict-database-name)
   (existing :initarg :existing :reader persistence-replay-conflict-existing)
   (incoming :initarg :incoming :reader persistence-replay-conflict-incoming))
  (:report
   (lambda (condition stream)
     (format stream "Conflicting ~A replay for stable ID ~S in graph ~S."
             (persistence-replay-conflict-record-kind condition)
             (persistence-replay-conflict-record-id condition)
             (persistence-replay-conflict-database-name condition)))))

(defun %same-graph-node-p (left right)
  (and (string= (tek9:node-id left) (tek9:node-id right))
       (equal (tek9:node-props left) (tek9:node-props right))))

(defun %same-graph-edge-p (left right)
  (and (string= (tek9:edge-id left) (tek9:edge-id right))
       (equal (tek9:edge-source left) (tek9:edge-source right))
       (equal (tek9:edge-predicate left) (tek9:edge-predicate right))
       (equal (tek9:edge-target left) (tek9:edge-target right))))

(defun %signal-replay-conflict (kind id database-name existing incoming)
  (error 'persistence-replay-conflict
         :record-kind kind
         :record-id id
         :database-name database-name
         :existing existing
         :incoming incoming))

(defun persist-graph-node-replay-safe (database node &key database-name)
  "Atomically insert NODE, accept an identical replay, or fail on ID conflict.

The read and possible write share one Tek9 write transaction. Concurrent writers
therefore cannot both observe a missing stable ID and silently replace one
another. Existing content is authoritative when the same ID carries different
properties."
  (check-type node tek9:node)
  (tek9:with-write-transaction (database)
    (let* ((id (tek9:node-id node))
           (existing (tek9:fetch-node database id :database-name database-name)))
      (cond
        ((null existing)
         (tek9:put-node database node :database-name database-name)
         :inserted)
        ((%same-graph-node-p existing node)
         :replayed)
        (t
         (%signal-replay-conflict :node id database-name existing node))))))

(defun persist-graph-edge-replay-safe (database edge &key database-name)
  "Atomically insert EDGE, accept an identical replay, or fail on ID conflict."
  (check-type edge tek9:edge)
  (tek9:with-write-transaction (database)
    (let* ((id (tek9:edge-id edge))
           (existing (tek9:fetch-edge database id :database-name database-name)))
      (cond
        ((null existing)
         (tek9:put-edge database edge :database-name database-name)
         :inserted)
        ((%same-graph-edge-p existing edge)
         :replayed)
        (t
         (%signal-replay-conflict :edge id database-name existing edge))))))

(defun persist-graph-nodes-replay-safe (database nodes &key database-name)
  "Persist NODES under one conflict-safe Tek9 transaction.

Any conflicting stable ID aborts the whole batch. The return value is a list of
:INSERTED/:REPLAYED outcomes corresponding to NODES."
  (tek9:with-write-transaction (database)
    (mapcar (lambda (node)
              (persist-graph-node-replay-safe database node
                                              :database-name database-name))
            nodes)))

(defun persist-graph-edges-replay-safe (database edges &key database-name)
  "Persist EDGES under one conflict-safe Tek9 transaction."
  (tek9:with-write-transaction (database)
    (mapcar (lambda (edge)
              (persist-graph-edge-replay-safe database edge
                                              :database-name database-name))
            edges)))
