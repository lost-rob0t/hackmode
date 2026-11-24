(in-package :hackmode-mcp)

;;;; JSON Schema derivation from the Star-Lang pentest IR.
;;;;
;;;; The compiled declarations carry :type (a primitive name, a qualified
;;;; scalar/enum reference, or (:list <type>)), :required, and scalar
;;;; :pattern. Everything MCP input schemas need is therefore derived from
;;;; the same graph the runtime executes against; there is no hand-written
;;;; schema table to drift.

(defun pentest-declaration (kind name)
  "Return the pentest library declaration of KIND named NAME, or NIL."
  (find-if (lambda (declaration)
             (and (eq (getf declaration :kind) kind)
                  (string= (getf declaration :name) name)))
           (hackmode-starlang:pentest-declarations)))

(defun require-declaration (kind name)
  "Return the pentest library declaration of KIND named NAME, failing loudly."
  (or (pentest-declaration kind name)
      (error "No ~a ~a in the pentest library." kind name)))

(defun simple-type-schema (name)
  "Return the JSON Schema object for a primitive IR type name."
  (cond
    ((string= name "string") (list :obj (cons "type" "string")))
    ((string= name "integer") (list :obj (cons "type" "integer")))
    ((string= name "map") (list :obj (cons "type" "object")))
    (t (error "Unsupported primitive IR type ~s." name))))

(defun scalar-schema (declaration)
  "Return the JSON Schema object for one scalar declaration."
  (let ((base (getf declaration :base))
        (pattern (getf declaration :pattern)))
    (cond
      ((string= base "string")
       (if pattern
           (list :obj (cons "type" "string") (cons "pattern" pattern))
           (list :obj (cons "type" "string"))))
      (t
       (error "Unsupported scalar base ~s in declaration ~a."
              base (getf declaration :name))))))

(defun resolve-type-schema (type)
  "Resolve one Star-Lang IR :TYPE value into a JSON Schema 2020-12 object."
  (cond
    ((stringp type)
     (cond
       ((member type '("string" "integer" "map") :test #'string=)
        (simple-type-schema type))
       (t
        (let ((declaration
                (find-if (lambda (candidate)
                           (string= (getf candidate :qualified-name) type))
                         (hackmode-starlang:pentest-declarations))))
          (unless declaration
            (error "Unresolved pentest type reference ~s." type))
          (ecase (getf declaration :kind)
            (:enum
             (list :obj (cons "type" "string")
                   (cons "enum" (copy-list (getf declaration :values)))))
            (:scalar (scalar-schema declaration)))))))
    ((and (consp type) (eq (first type) :list))
     (unless (= (length type) 2)
       (error "Unsupported list type ~s." type))
     (list :obj (cons "type" "array")
           (cons "items" (resolve-type-schema (second type)))))
    (t (error "Unsupported pentest IR type ~s." type))))

(defun message-input-schema (message-name
                             &key (optional-required '("runId")))
  "Derive the MCP input schema object for MESSAGE-NAME.

Optional-required names (default: runId) stay in properties but leave the
required list: the server generates a conforming runId when the caller
omits it. The wire message always carries one."
  (let* ((declaration (require-declaration :message message-name))
         (properties (list :obj))
         (required '()))
    (dolist (field (getf declaration :fields))
      (let ((name (getf field :name)))
        (setf properties
              (append properties
                      (list (cons name
                                  (resolve-type-schema (getf field :type))))))
        (when (and (getf field :required)
                   (not (member name optional-required :test #'string=)))
          (push name required))))
    (list :obj
          (cons "type" "object")
          (cons "properties" properties)
          (cons "required" (nreverse required)))))
