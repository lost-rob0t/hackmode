(in-package :hackmode-starlang)

(defparameter *default-dataset* "hackmode"
  "Dataset stamped onto pentest wire documents built from Hackmode runs.")

(defvar *pentest-graph* nil
  "Cached loaded Star-Lang graph of the pentest tool library.")

(defun pentest-spec-pathname ()
  (asdf:system-relative-pathname :hackmode-starlang "spec/pentest.star"))

(defun load-pentest-graph (&key (reload nil))
  "Load (and cache) the org.hackmode/pentest@1 Star-Lang library graph."
  (when (or reload (null *pentest-graph*))
    (setf *pentest-graph*
          (star-lang.api:load-star-file (pentest-spec-pathname))))
  *pentest-graph*)

(defun pentest-root (&key (reload nil))
  (star-lang.loader:loaded-graph-root (load-pentest-graph :reload reload)))

(defparameter *required-ir-version* 2
  "Normalized IR version this bridge's declaration accessors are written for.")

(defparameter *required-ir-schema* "org.star-lang/normalized-ir@2"
  "Normalized IR schema discriminator this bridge's accessors expect.")

(defun pentest-compiled (&key (reload nil))
  (let ((compiled
          (star-lang.loader:library-node-compiled (pentest-root :reload reload))))
    (unless (and (eql (getf compiled :ir-version) *required-ir-version*)
                 (string= (getf compiled :ir-schema) *required-ir-schema*))
      (error "Pentest library IR is ~a/~a; this bridge requires ~a/~a. Pin a matching star-lang commit."
             (getf compiled :ir-version) (getf compiled :ir-schema)
             *required-ir-version* *required-ir-schema*))
    compiled))

(defun pentest-library-name (&key (reload nil))
  (star-lang.loader:library-node-name (pentest-root :reload reload)))

(defun pentest-library-version (&key (reload nil))
  (star-lang.loader:library-node-version (pentest-root :reload reload)))

(defun pentest-declarations (&key (reload nil))
  (getf (pentest-compiled :reload reload) :declarations))

(defun declaration-of-kind (kind name &key (reload nil))
  (find-if (lambda (declaration)
             (and (eq (getf declaration :kind) kind)
                  (string= (getf declaration :name) name)))
           (pentest-declarations :reload reload)))

(defun pentest-enum-values (name &key (reload nil))
  (let ((declaration (declaration-of-kind :enum name :reload reload)))
    (unless declaration
      (error "No enum ~a in the pentest library." name))
    (getf declaration :values)))

(defun pentest-declaration-fields (kind name &key (reload nil))
  (let ((declaration (declaration-of-kind kind name :reload reload)))
    (unless declaration
      (error "No ~a ~a in the pentest library." kind name))
    (mapcar (lambda (field) (getf field :name))
            (getf declaration :fields))))

(defun declared-tools (&key (reload nil))
  (pentest-enum-values "tool-name" :reload reload))

(defun declared-recon-tools (&key (reload nil))
  (pentest-enum-values "recon-tool" :reload reload))

(defun declared-vuln-tools (&key (reload nil))
  (pentest-enum-values "vuln-tool" :reload reload))

(defun tool-kind-for (tool &key (reload nil))
  "Return :RECON or :VULN for a declared pentest tool name."
  (let ((tool (string-downcase (string tool))))
    (cond
      ((find tool (declared-recon-tools :reload reload) :test #'string=)
       :recon)
      ((find tool (declared-vuln-tools :reload reload) :test #'string=)
       :vuln)
      (t
       (error "Unknown pentest tool ~a." tool)))))

(defun make-tool-run-document
    (run-id kind tool target argv status
     &key exit-code stdout stderr raw
       (dataset *default-dataset*)
       (graph (load-pentest-graph)))
  "Build the wire tool-run document for one executed pentest tool run."
  (handler-case
      (star-lang.api:create-document
       graph "tool-run"
       (append (list :run-id (string run-id)
                     :kind (string-downcase (string kind))
                     :tool (string-downcase (string tool))
                     :target target
                     :argv argv
                     :status (string-downcase (string status)))
               (when exit-code (list :exit-code exit-code))
               (when stdout (list :stdout stdout))
               (when stderr (list :stderr stderr))
               (list :raw (or raw '())))
       :dataset dataset)
    (error (condition)
      (error "Building tool-run wire document failed: ~a" condition))))

(defun encode-tool-run (document)
  (star-lang.api:encode-document document))

(defun make-vuln-finding-document
    (run-id tool target template-id severity evidence
     &key host matched-at raw
       (dataset *default-dataset*)
       (graph (load-pentest-graph)))
  "Build the wire vuln-finding document preserving the exact evidence value."
  (handler-case
      (star-lang.api:create-document
       graph "vuln-finding"
       (append (list :run-id (string run-id)
                     :tool (string-downcase (string tool))
                     :target target
                     :template-id template-id
                     :severity (string-downcase (string severity))
                     :evidence evidence)
               (when host (list :host host))
               (when matched-at (list :matched-at matched-at))
               (list :raw (or raw '())))
       :dataset dataset)
    (error (condition)
      (error "Building vuln-finding wire document failed: ~a" condition))))

(defun encode-vuln-finding (document)
  (star-lang.api:encode-document document))
