(in-package :hackmode-database)


;; default to the one from tek9
(defun put-doc (database document &key (database-name "std"))

  (tek9:put* database document))
