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
