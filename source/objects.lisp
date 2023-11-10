(in-package :hackmode)



(define-condition invalid-object-error (error)
  ((slot :initarg :slot :initform nil :accessor invalid-object-slot))
  (:report (lambda (condition stream))
   (format stream "Slot: ~a is a required slot." (invalid-object-slot condition))))

(deftype hackmode-obj)

(defclass exploit ()
  ((name :initarg :name :accessor exploit-name :initform (error "Invalid exploit Error: exploit requires a name"))
   (platform :initarg :platform :accessor exploit-platform :initform (error "Invalid exploit Error: exploit requires a platform"))
   (help :initarg :help :accessor exploit-help :initform nil)
   (options :initarg :options :accessor exploit-options :initform nil)
   (func :initarg :func :accessor exploit-func :initform (lambda () (format t "Its an exploit!")))
   (setup :initarg :exploit-setup :accessor exploit-setup :initform nil)))



(defclass exploit-option ()
  ((name :initarg :name :accessor exploit-option-name :initform (error 'invalid-object-error :slot :name))
   (option-type :initarg :option-type :accessor exploit-option-type :initform (error 'invalid-object-error :slot :option-type))
   (documentation :initarg :documentation :accessor exploit-option-documentation :initform (progn (warn "You Should document your exploit options.") "option for exploit."))))


;; TODO make to to call the creation of this at the main function.
(defclass history ()
  ((path :initarg :path :initform history-path :accessor history-path)
   (entries :initarg :history-entries :accessor history-entries :initform nil)))


(defclass history-entry ()
  ((time :initarg :time :initform (local-time:timestamp-to-unix (local-time:now) ) :reader history-time)
   (command :initarg :command :initform (error 'invalid-object-error :slot :commmand) :reader history-command)))




;; (defmethod insert-history (())
;;   (setf (history-entries *history*) (push *last-command* (history-entries *history*)))
;;   (with-open-file (str (history-path *history*) :direction :output :if-exists :supersede
;;                                                 :if-does-not-exist :create)
;;     (write-sequence (history-entries *history*) str)))



;; (defun* make-history-entry (&rest (command string))
;;   (make-instance 'history-entry :command (apply #'list command)))

;; (defun load-history ()
;;   ;; Note disable read-eval on reading history!!
;;   (let ((*read-eval* nil))
;;     (with-open-file (str (history-path *history*) :direction :input :if-does-not-exist :create)
;;       (setf (history-entries *history*)  (read-from-string (read-line str))))))



;; (defvar *history-hook* (make-instance 'nhooks:hook-any :handlers (list #'insert-history)))


;; (defmethod run ((exploit exploit))
;;   (funcall (exploit-func exploit))
;;   (nhooks:run-hook '*history-hook* (make-history-entry run (exploit-name exploit))))


;; (defmethod use ((exploit exploit))
;;   (setq *current-package* exploit))
