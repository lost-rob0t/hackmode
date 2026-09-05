(in-package :hackmode-tests)

(defun run-expert-objective-tests ()
  (let* ((goal
           (hackmode:make-expert-objective-clause
            :kind :goal
            :predicate "final_identity"
            :arguments '(:uid 0 :root-equivalent t)))
         (foothold
           (hackmode:make-expert-objective-clause
            :kind :precondition
            :predicate "foothold"
            :arguments '(:required t)))
         (proof
           (hackmode:make-expert-objective-clause
            :kind :evidence
            :predicate "authenticated_execution"
            :arguments '(:proves "final_identity")))
         (stop
           (hackmode:make-expert-objective-clause
            :kind :stop
            :predicate "on_goal"
            :arguments '(:value t)))
         (limit
           (hackmode:make-expert-objective-limit
            :name "provider-actions"
            :maximum 25))
         (objective
           (hackmode:make-expert-objective
            :id "root-objective"
            :version "1"
            :clauses (list goal foothold proof stop)
            :limits (list limit)
            :granted-capabilities '("subdomain-enumerate" "http-probe"))))
    (assert-equal "root-objective"
                  (hackmode:expert-objective-id objective)
                  "objective identity is retained")
    (assert-equal "1"
                  (hackmode:expert-objective-version objective)
                  "objective version is retained")
    (assert-equal '(:uid 0 :root-equivalent t)
                  (hackmode:expert-objective-clause-arguments goal)
                  "uid-0 goal remains typed data")
    (assert-equal '(:required t)
                  (hackmode:expert-objective-clause-arguments foothold)
                  "foothold prerequisite remains explicit")
    (assert-equal '("http-probe" "subdomain-enumerate")
                  (hackmode:expert-objective-granted-capabilities objective)
                  "capability grants are normalized deterministically")
    (assert-equal 25
                  (hackmode:expert-objective-limit-maximum
                   (first (hackmode:expert-objective-limits objective)))
                  "budget limit remains typed")
    (let ((clauses (hackmode:expert-objective-clauses objective))
          (capabilities (hackmode:expert-objective-granted-capabilities objective)))
      (setf (car clauses) :tampered
            (car capabilities) "tampered")
      (assert-equal :goal
                    (hackmode:expert-objective-clause-kind
                     (first (hackmode:expert-objective-clauses objective)))
                    "returned clause list cannot mutate objective")
      (assert-equal "http-probe"
                    (first (hackmode:expert-objective-granted-capabilities objective))
                    "returned capability list cannot mutate objective"))
    (let* ((caller-id (copy-seq "mutable-objective"))
           (caller-version (copy-seq "version-1"))
           (isolated
             (hackmode:make-expert-objective
              :id caller-id
              :version caller-version
              :clauses (list goal)
              :granted-capabilities nil)))
      (setf (char caller-id 0) #\X
            (char caller-version 0) #\X)
      (assert-equal "mutable-objective"
                    (hackmode:expert-objective-id isolated)
                    "caller-owned ID mutation cannot rewrite objective identity")
      (assert-equal "version-1"
                    (hackmode:expert-objective-version isolated)
                    "caller-owned version mutation cannot rewrite objective version")
      (let ((returned-id (hackmode:expert-objective-id isolated))
            (returned-version (hackmode:expert-objective-version isolated)))
        (setf (char returned-id 0) #\Y
              (char returned-version 0) #\Y)
        (assert-equal "mutable-objective"
                      (hackmode:expert-objective-id isolated)
                      "returned ID mutation cannot rewrite objective identity")
        (assert-equal "version-1"
                      (hackmode:expert-objective-version isolated)
                      "returned version mutation cannot rewrite objective version")))
    (let* ((caller-predicate (copy-seq "final_identity"))
           (caller-limit-name (copy-seq "provider-actions"))
           (caller-capability (copy-seq "http-probe"))
           (isolated-clause
             (hackmode:make-expert-objective-clause
              :kind :goal
              :predicate caller-predicate
              :arguments '(:uid 0)))
           (isolated-limit
             (hackmode:make-expert-objective-limit
              :name caller-limit-name
              :maximum 3))
           (isolated
             (hackmode:make-expert-objective
              :id "value-freeze"
              :version "1"
              :clauses (list isolated-clause)
              :limits (list isolated-limit)
              :granted-capabilities (list caller-capability))))
      (setf (char caller-predicate 0) #\X
            (char caller-limit-name 0) #\X
            (char caller-capability 0) #\X)
      (assert-equal "final_identity"
                    (hackmode:expert-objective-clause-predicate isolated-clause)
                    "caller-owned predicate mutation cannot rewrite objective semantics")
      (assert-equal "provider-actions"
                    (hackmode:expert-objective-limit-name isolated-limit)
                    "caller-owned limit-name mutation cannot rewrite objective budget identity")
      (assert-equal "http-probe"
                    (first (hackmode:expert-objective-granted-capabilities isolated))
                    "caller-owned capability mutation cannot rewrite objective grants")
      (let ((returned-predicate
              (hackmode:expert-objective-clause-predicate isolated-clause))
            (returned-limit-name
              (hackmode:expert-objective-limit-name isolated-limit))
            (returned-capability
              (first (hackmode:expert-objective-granted-capabilities isolated))))
        (setf (char returned-predicate 0) #\Y
              (char returned-limit-name 0) #\Y
              (char returned-capability 0) #\Y)
        (assert-equal "final_identity"
                      (hackmode:expert-objective-clause-predicate isolated-clause)
                      "returned predicate mutation cannot rewrite objective semantics")
        (assert-equal "provider-actions"
                      (hackmode:expert-objective-limit-name isolated-limit)
                      "returned limit-name mutation cannot rewrite objective budget identity")
        (assert-equal "http-probe"
                      (first (hackmode:expert-objective-granted-capabilities isolated))
                      "returned capability mutation cannot rewrite objective grants")))
    (dolist (bad `((:clause-kind
                    ,(lambda ()
                       (hackmode:make-expert-objective-clause
                        :kind :unknown :predicate "x")))
                   (:empty-predicate
                    ,(lambda ()
                       (hackmode:make-expert-objective-clause
                        :kind :goal :predicate "")))
                   (:negative-limit
                    ,(lambda ()
                       (hackmode:make-expert-objective-limit
                        :name "actions" :maximum -1)))
                   (:duplicate-capability
                    ,(lambda ()
                       (hackmode:make-expert-objective
                        :id "dup" :version "1"
                        :clauses (list goal)
                        :granted-capabilities '("http-probe" "http-probe"))))))
      (handler-case
          (progn
            (funcall (second bad))
            (error "invalid objective case ~s unexpectedly succeeded" (first bad)))
        (hackmode:invalid-expert-objective () t)))
    t))
