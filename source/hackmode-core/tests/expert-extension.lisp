(in-package :hackmode-tests)

(defun run-expert-extension-tests ()
  (let* ((objective
           (hackmode:make-expert-objective
            :id "root-objective"
            :version "1"
            :clauses
            (list
             (hackmode:make-expert-objective-clause
              :kind :goal :predicate "final_identity" :arguments '(:uid 0))
             (hackmode:make-expert-objective-clause
              :kind :precondition :predicate "foothold" :arguments '(:required t)))
            :granted-capabilities '("http-probe" "subdomain-enumerate")))
         (recon
           (hackmode:make-expert-extension
            :id "recon"
            :version "1"
            :objective-predicates '("foothold")
            :required-capabilities '("subdomain-enumerate")
            :authority :active
            :strategies '(:symbolic :direct)))
         (privilege
           (hackmode:make-expert-extension
            :id "privilege"
            :version "1"
            :objective-predicates '("final_identity")
            :required-capabilities '("shell-session")
            :authority :active
            :strategies '(:symbolic)))
         (registry
           (hackmode:register-expert-extension
            (hackmode:register-expert-extension
             (hackmode:make-expert-extension-registry)
             privilege)
            recon)))
    (assert-equal '("privilege" "recon")
                  (mapcar #'hackmode:expert-extension-id
                          (hackmode:list-expert-extensions registry))
                  "registry is deterministic by stable extension ID")
    (assert-equal '("recon")
                  (mapcar
                   #'hackmode:expert-extension-id
                   (hackmode:applicable-expert-extensions
                    registry objective
                    :authority :active
                    :strategy :symbolic
                    :available-capabilities
                    '("subdomain-enumerate" "http-probe")))
                  "missing required capability rejects otherwise matching extension")
    (assert-equal nil
                  (hackmode:applicable-expert-extensions
                   registry objective
                   :authority :passive
                   :strategy :symbolic
                   :available-capabilities '("subdomain-enumerate"))
                  "active-only extension is rejected under passive authority")
    (assert-equal '("recon")
                  (mapcar
                   #'hackmode:expert-extension-id
                   (hackmode:applicable-expert-extensions
                    registry objective
                    :authority :active
                    :strategy :direct
                    :available-capabilities '("subdomain-enumerate")))
                  "reasoning strategy selection remains orthogonal to authority")
    (let ((copy (hackmode:list-expert-extensions registry)))
      (setf (car copy) :tampered)
      (assert-equal "privilege"
                    (hackmode:expert-extension-id
                     (first (hackmode:list-expert-extensions registry)))
                    "registry accessor is defensive"))
    (let* ((id (copy-seq "stable-extension"))
           (version (copy-seq "v1"))
           (extension
             (hackmode:make-expert-extension
              :id id
              :version version
              :objective-predicates '("foothold")
              :required-capabilities nil
              :authority :passive
              :strategies '(:symbolic))))
      (setf (char id 0) #\X
            (char version 0) #\X)
      (assert-equal "stable-extension"
                    (hackmode:expert-extension-id extension)
                    "extension snapshots caller-owned ID strings")
      (assert-equal "v1"
                    (hackmode:expert-extension-version extension)
                    "extension snapshots caller-owned version strings")
      (let ((returned-id (hackmode:expert-extension-id extension))
            (returned-version (hackmode:expert-extension-version extension)))
        (setf (char returned-id 0) #\Y
              (char returned-version 0) #\Y)
        (assert-equal "stable-extension"
                      (hackmode:expert-extension-id extension)
                      "extension ID accessor returns a defensive snapshot")
        (assert-equal "v1"
                      (hackmode:expert-extension-version extension)
                      "extension version accessor returns a defensive snapshot")))
    (handler-case
        (progn
          (hackmode:register-expert-extension registry recon)
          (error "duplicate extension unexpectedly registered"))
      (hackmode:invalid-expert-extension () t))
    t))
