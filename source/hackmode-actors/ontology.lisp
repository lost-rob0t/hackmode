(in-package :hackmode-actors)

(define-condition ontology-error (error)
  ((message :initarg :message :reader ontology-error-message))
  (:report (lambda (condition stream)
             (format stream "Hackmode ontology error: ~a"
                     (ontology-error-message condition)))))

(define-condition ontology-message-error (ontology-error) ())

(defvar *ontology-spec-directory* nil
  "Directory holding hackmode-core.star and actors/. Defaults to the tracked
spec/ directory at the repository root next to this system's source tree.")

(defun ontology-spec-directory ()
  (or *ontology-spec-directory*
      (setf *ontology-spec-directory*
            (merge-pathnames
             (make-pathname :directory '(:relative :up :up "spec"))
             (asdf:system-source-directory :hackmode-actors)))))

(defun ontology-library-file ()
  (merge-pathnames "hackmode-core.star" (ontology-spec-directory)))

(defun ontology-actor-files ()
  (sort (directory
         (merge-pathnames "actors/*.star" (ontology-spec-directory)))
        #'string< :key #'namestring))

(defvar *hackmode-ontology* nil
  "Memoized compiled ontology: (LIBRARY ACTOR-IRS . MANIFEST).")

(defun load-hackmode-ontology (&key (force nil))
  "Compile hackmode-core.star plus every actor spec and return the manifest.

Returns (VALUES LIBRARY ACTOR-IRS MANIFEST). The compiled graph is memoized;
pass FORCE to recompile from source."
  (when (or force (null *hackmode-ontology*))
    (let* ((library (starlangcompiler:load-star-form (ontology-library-file)))
           (actors (mapcar #'starlangcompiler:compile-actor-file
                           (ontology-actor-files)))
           (manifest (starlangcompiler:emit-portable-manifest library actors)))
      (setf *hackmode-ontology* (cons library (cons actors manifest)))))
  (values (first *hackmode-ontology*)
          (second *hackmode-ontology*)
          (rest (rest *hackmode-ontology*))))

(defun hackmode-ontology-library ()
  "Return the compiled spec library, loading it when necessary."
  (nth-value 0 (load-hackmode-ontology)))

(defun hackmode-ontology-actors ()
  "Return the compiled actor IR list, loading the ontology when necessary."
  (nth-value 1 (load-hackmode-ontology)))

(defun hackmode-ontology-manifest ()
  "Return the portable wire manifest for the whole actor system."
  (nth-value 2 (load-hackmode-ontology)))

(defun ontology-library-name ()
  "Return the ontology library identity string."
  (getf (hackmode-ontology-library) :name))

(defun ontology-declarations ()
  (getf (hackmode-ontology-library) :declarations))

(defun ontology-declaration (kind name)
  "Return the compiled declaration named NAME, or signal ONTOLOGY-ERROR."
  (or (find name (ontology-declarations)
            :test #'string=
            :key (lambda (declaration) (getf declaration :name)))
      (error 'ontology-error
             :message (format nil "no ~a declaration named ~s" kind name))))

(defun ontology-document-names ()
  (sort (mapcar (lambda (d) (getf d :name))
                (remove :document (ontology-declarations)
                        :key (lambda (d) (getf d :kind)) :test-not #'eq))
        #'string<))

(defun ontology-predicate-names ()
  (sort (mapcar (lambda (d) (getf d :name))
                (remove :predicate (ontology-declarations)
                        :key (lambda (d) (getf d :kind)) :test-not #'eq))
        #'string<))

(defun ontology-message-declaration (message-type)
  (or (find message-type (ontology-declarations)
            :test #'string=
            :key (lambda (d) (getf d :name)))
      (error 'ontology-message-error
             :message (format nil "unknown ontology message type ~s" message-type))))

(defun ontology-actor-names ()
  (mapcar (lambda (ir) (getf ir :name)) (hackmode-ontology-actors)))

(defun ontology-actor-ir (name)
  (or (find name (hackmode-ontology-actors)
            :test #'string= :key (lambda (ir) (getf ir :name)))
      (error 'ontology-error
             :message (format nil "no ontology actor named ~s" name))))

(defun ontology-actor-accepts (name)
  (getf (ontology-actor-ir name) :accepts))

(defun ontology-actor-produces (name)
  (getf (ontology-actor-ir name) :produces))

(defun ontology-actor-handler (name)
  "Return the host handler identifier declared by the actor spec."
  (getf (ontology-actor-ir name) :handler))

(defparameter *wire-message-type-key* "type")
(defparameter *wire-message-payload-key* "payload")

(defun make-ontology-wire-message (message-type payload)
  "Return a wire message alist for MESSAGE-TYPE with a jsown-style PAYLOAD."
  (list (cons *wire-message-type-key* message-type)
        (cons *wire-message-payload-key* payload)))

(defun ontology-wire-message-type (message)
  (cdr (assoc *wire-message-type-key* message :test #'string=)))

(defun ontology-wire-message-payload (message)
  (cdr (assoc *wire-message-payload-key* message :test #'string=)))

(defun %payload-value (payload field-name)
  (cdr (assoc field-name payload :test #'string=)))

(defun %enum-values (type-name)
  (let ((declaration
          (find type-name (ontology-declarations)
                :test #'string=
                :key (lambda (d) (or (getf d :qualified-name)
                                     (getf d :name))))))
    (when (eq (getf declaration :kind) :enum)
      (getf declaration :values))))

(defun %wire-type-matches-p (type value)
  (let ((enum-values (%enum-values type)))
    (cond
      (enum-values
       (and (stringp value) (member value enum-values :test #'string=)))
      ((string= type "string") (stringp value))
      ((string= type "integer") (integerp value))
      ((string= type "decimal") (realp value))
      ((string= type "boolean") (booleanp value))
      ((string= type "map")
       (and (listp value)
            (every (lambda (pair) (and (consp pair) (stringp (car pair)))) value)))
      ((string= type "reference") (stringp value))
      ((string= type "any") t)
      ((string= type "symbol") (symbolp value))
      (t
       ;; List constructors and unknown refinements pass structural checks only.
       t))))

(defun validate-ontology-message (message-type payload)
  "Validate PAYLOAD (jsown-style alist) against the compiled MESSAGE-TYPE.

Signals ONTOLOGY-MESSAGE-ERROR when a required field is missing or a field
value does not match its declared wire type. Unknown payload keys are left to
the projection layer; the ontology is a contract for producers, and extra
runtime data must not be silently destroyed by validation."
  (let ((declaration (ontology-message-declaration message-type)))
    (dolist (field (getf declaration :fields))
      (let* ((name (getf field :name))
             (type (getf field :type))
             (value (%payload-value payload name)))
        (cond
          ((getf field :required)
           (unless value
             (error 'ontology-message-error
                    :message (format nil "message ~s requires field ~s"
                                     message-type name)))
           (unless (%wire-type-matches-p type value)
             (error 'ontology-message-error
                    :message (format nil "field ~s of ~s is not a ~s: ~s"
                                     name message-type type value))))
          ((and value (not (%wire-type-matches-p type value)))
           (error 'ontology-message-error
                  :message (format nil "field ~s of ~s is not a ~s: ~s"
                                   name message-type type value))))))
    t))

;;; --- Canonical StarIntel spec consumption -----------------------------------
;;;
;;; The ontology imports the canonical starintel core library
;;; (org.starintel/core@1) with a full SHA-256 lock over the vendored
;;; byte-identical copy in spec/vendor/. The loader verifies the digest at
;;; load time, so dtype support below is derived from the canonical
;;; vocabulary rather than hardcoded assumptions.

(defparameter *starintel-core-library-name* "org.starintel/core@1")

(defparameter *starintel-core-digest*
  "sha256:0c6a50a12a9779a0e760cd48d6e4f3bf3fdadf04e61ec3cb67f8685fe64499a5")

(defvar *starintel-graph* nil
  "Memoized loaded ontology graph including the imported starintel core.")

(defun clear-hackmode-ontology ()
  "Forget the memoized compiled ontology so the next load recompiles."
  (setf *hackmode-ontology* nil
        *starintel-graph* nil)
  t)

(defun hackmode-starintel-graph (&key (force nil))
  "Load the digest-locked ontology graph (root + imported starintel core).

Returns the loader graph; the root library node carries the Hackmode
vocabulary, the imported node carries the canonical StarIntel vocabulary."
  (when (or force (null *starintel-graph*))
    (setf *starintel-graph*
          (star-lang.loader:load-star-file (ontology-library-file)
                                        :allow-network nil)))
  *starintel-graph*)

(defun starintel-core-node ()
  "Return the loaded canonical starintel core library node."
  (find *starintel-core-library-name*
        (star-lang.loader:loaded-graph-libraries (hackmode-starintel-graph))
        :key #'star-lang.loader:library-node-name
        :test #'string=))

(defun starintel-core-declarations ()
  (let ((node (starintel-core-node)))
    (and node
         (getf (star-lang.loader:library-node-compiled node) :declarations))))

(defun starintel-dtype-declared-p (dtype)
  "Return true when the canonical starintel core vocabulary declares DTYPE."
  (and (find dtype (starintel-core-declarations)
             :key (lambda (declaration) (getf declaration :name))
             :test #'string=)
       t))
