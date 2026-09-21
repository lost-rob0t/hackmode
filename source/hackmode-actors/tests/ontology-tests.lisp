(defpackage :hackmode-actors-tests
  (:nicknames :hm-actors-tests)
  (:use :cl)
  (:export :run-all-tests))

(in-package :hackmode-actors-tests)

(defun assert-equal (expected actual &optional (label "values"))
  (assert (equal expected actual) ()
          "Expected ~a to be ~s, got ~s" label expected actual))

(defun signals-condition-p (condition-type thunk)
  "Return true when THUNK signals a condition of CONDITION-TYPE."
  (handler-case (funcall thunk)
    (condition (condition) (typep condition condition-type))
    (:no-error (&rest values) (declare (ignore values)) nil)))

(defun run-ontology-load-test ()
  (multiple-value-bind (library actors manifest)
      (hackmode-actors:load-hackmode-ontology :force t)
    (assert (string= "dev.hackmode/core@1"
                     (getf library :name)))
    (assert-equal 6 (length actors) "ontology actor count")
    (assert-equal 1 (getf manifest :wire-version) "manifest wire version")
    (assert-equal
     '("asset-monitor" "capture-supervisor" "expert-advisor"
       "outbox" "provider-dispatcher" "replay")
     (sort (hackmode-actors:ontology-actor-names) #'string<)
     "actor names")
    (assert (member "http-exchange"
                    (hackmode-actors:ontology-document-names)
                    :test #'string=))
    (assert (member "resolves-to"
                    (hackmode-actors:ontology-predicate-names)
                    :test #'string=))))

(defun run-ontology-contract-test ()
  (assert-equal
   '("hackmode/asset-discovered@1")
   (hackmode-actors:ontology-actor-accepts "asset-monitor")
   "asset-monitor accepts")
  (assert-equal
   '("hackmode/enqueue-document@1")
   (hackmode-actors:ontology-actor-produces "asset-monitor")
   "asset-monitor produces")
  (assert-equal
   "hackmode-actor-outbox"
   (hackmode-actors:ontology-actor-handler "outbox")
   "outbox handler identifier")
  ;; The ontology and the StarIntel 0.10.1 authority agree on required fields.
  (let ((message (hackmode-actors:ontology-message-declaration
                  "hackmode/asset-discovered@1")))
    (assert-equal "assetId"
                  (getf (first (getf message :fields)) :name)
                  "first asset-discovered field")))

(defun run-message-validation-test ()
  (flet ((signals-message-error (payload)
           (signals-condition-p
            'hackmode-actors:ontology-message-error
            (lambda ()
              (hackmode-actors:validate-ontology-message
               "hackmode/asset-discovered@1" payload)))))
    ;; Valid payload passes.
    (assert
     (hackmode-actors:validate-ontology-message
      "hackmode/asset-discovered@1"
      '(("assetId" . "abc") ("kind" . "domain"))))
    ;; Missing required field fails.
    (assert (signals-message-error '(("kind" . "domain"))))
    ;; Wrong type fails.
    (assert (signals-message-error '(("assetId" . 42) ("kind" . "domain"))))
    ;; Enum membership is enforced.
    (assert (signals-message-error
             '(("assetId" . "abc") ("kind" . "not-a-kind"))))
    ;; Unknown message type fails.
    (assert
     (signals-condition-p
      'hackmode-actors:ontology-message-error
      (lambda ()
        (hackmode-actors:validate-ontology-message "hackmode/nothing@9" '()))))
    ;; Wire message helpers round-trip.
    (let ((wire (hackmode-actors:make-ontology-wire-message
                 "hackmode/drain-outbox@1" '())))
      (assert-equal "hackmode/drain-outbox@1"
                    (hackmode-actors:ontology-wire-message-type wire)
                    "wire type")
      (assert-equal '() (hackmode-actors:ontology-wire-message-payload wire)
                    "wire payload"))))

(defun run-canonical-spec-consumption-test ()
  ;; The ontology imports the canonical starintel core with a digest lock.
  (let* ((graph (hackmode-actors:hackmode-starintel-graph :force t))
         (libraries (mapcar #'star-lang.loader:library-node-name
                            (star-lang.loader:loaded-graph-libraries graph)))
         (core (hackmode-actors::starintel-core-node)))
    (assert (member hackmode-actors:*starintel-core-library-name*
                    libraries
                    :test #'string=))
    ;; Digest lock verified at load time and exposed by the loaded node.
    (assert (string= hackmode-actors:*starintel-core-digest*
                     (star-lang.loader:library-node-digest core))
            ()
            "canonical starintel core digest mismatch")
    ;; Projection support derives from the canonical vocabulary.
    (dolist (dtype '("domain" "host" "url" "operation" "research-node"
                     "http-transaction" "web-capture"))
      (assert (hackmode-actors:starintel-dtype-declared-p dtype) ()
              "canonical core should declare ~a" dtype))
    ;; The 0.10.1 vocabulary has no port/finding/cert dtypes; hackmode keeps
    ;; them local-only and the projection must refuse them.
    (dolist (dtype '("port" "finding" "cert"))
      (assert (not (hackmode-actors:starintel-dtype-declared-p dtype)) ()
              "canonical core should NOT declare ~a" dtype))
    (assert
     (signals-condition-p
      'hackmode-actors:ontology-error
      (lambda ()
        (hackmode-actors:make-starintel-envelope
         "x" "star-intel" "port" (jsown:empty-object)))))))

(defun run-ontology-tests ()
  (run-ontology-load-test)
  (run-ontology-contract-test)
  (run-message-validation-test)
  (run-canonical-spec-consumption-test))
