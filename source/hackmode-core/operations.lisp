(in-package :hackmode)

(defvar *operations-database*
  (tek9:new-database "operations" :path hackmode-operations-database))

(nhooks:add-hook *startup-hook*
                 (lambda ()
                   (ensure-operations-database-open)))

(defclass operation (meta)
  ((working-dir :initarg :dir :accessor operation-dir
                :initform (namestring (uiop/os:getcwd)) :type string)
   (name :initarg :name :accessor operation-name :initform "" :type string)
   (description :initarg :description :accessor operation-description
                :initform "" :type string)))

(conspack:defencoding operation
  doc-id tags dtype date-added date-updated operation tool
  working-dir name description)

(defvar *current-operation* nil "The current Hackmode operation.")

(defun ensure-operations-database-open ()
  "Open the operation registry if it is not already open."
  (unless (tek9:db-is-open-p *operations-database*)
    (tek9:open-database *operations-database*))
  *operations-database*)

(defun new-operation (name
                      &optional
                        (path (uiop:merge-pathnames* ".hackmode/" (uiop:getcwd)))
                        (description "Hackmode operation"))
  "Create and persist an operation named NAME."
  (ensure-operations-database-open)
  (let* ((dir (namestring (pathname path)))
         (doc (make-instance 'operation
                             :id name
                             :name name
                             :operation name
                             :description description
                             :dir dir
                             :dtype "operation")))
    (tek9:put* *operations-database* doc :id name)
    doc))

(defun select-operation (name)
  "Return the persisted operation named NAME, or NIL."
  (ensure-operations-database-open)
  (tek9:fetch* *operations-database* name))

(defun list-operations ()
  "Return all persisted operations sorted by name."
  (ensure-operations-database-open)
  (let (operations)
    (tek9:map-database
     *operations-database*
     :map-fn (lambda (key document)
               (declare (ignore key))
               (let ((value (tek9:doc-value document)))
                 (when (typep value 'operation)
                   (push value operations)))))
    (sort operations #'string< :key #'operation-name)))

(defun current-operation ()
  "Return the active operation object, or NIL."
  *current-operation*)

(defun operation-status (&optional (operation *current-operation*))
  "Return a stable plist describing OPERATION's current local state."
  (when operation
    (list :name (operation-name operation)
          :description (operation-description operation)
          :directory (operation-dir operation)
          :database-open (and *db* (tek9:db-is-open-p *db*)))))

(defun use-operation (name)
  "Select NAME as the current operation and open its local Tek9 store."
  (let* ((op (select-operation name))
         (dir (if op
                  (operation-dir op)
                  (error "No such operation ~s. Create it with NEW-OPERATION first." name))))
    (setf *current-operation* op)
    (uiop:ensure-all-directories-exist (list dir))
    (when (and *db* (tek9:db-is-open-p *db*))
      (tek9:close-database *db*))
    (setf *db*
          (tek9:new-database
           name
           :path (uiop:merge-pathnames*
                  (uiop:parse-unix-namestring dir)
                  ".hackmode/")))
    (tek9:open-database *db*)
    (uiop:chdir dir)
    op))
