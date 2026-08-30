(in-package :hackmode-tests)

(defun run-expert-budget-tests ()
  (let* ((goal (hackmode:make-expert-objective-clause
                :kind :goal :predicate "root" :arguments '(:uid 0)))
         (objective (hackmode:make-expert-objective
                     :id "root" :version "1"
                     :clauses (list goal)
                     :limits (list (hackmode:make-expert-objective-limit
                                    :name "provider-actions" :maximum 2))
                     :granted-capabilities '("http-probe")))
         (state (hackmode:make-expert-budget-state
                 objective :operation "op-1" :run-id "run-1")))
    (assert-equal 2
                  (hackmode:expert-budget-remaining state "provider-actions")
                  "fresh budget exposes remaining allowance")
    (assert-equal nil
                  (hackmode:expert-budget-exhausted-p state)
                  "fresh budget is not exhausted")
    (let ((once (hackmode:expert-budget-consume
                 state "provider-actions" :amount 1)))
      (assert-equal 1
                    (hackmode:expert-budget-remaining once "provider-actions")
                    "consumption returns a new state")
      (assert-equal 2
                    (hackmode:expert-budget-remaining state "provider-actions")
                    "source budget state remains immutable")
      (let ((twice (hackmode:expert-budget-consume
                    once "provider-actions" :amount 1)))
        (assert-equal 0
                      (hackmode:expert-budget-remaining twice "provider-actions")
                      "budget reaches zero exactly")
        (assert-equal t
                      (hackmode:expert-budget-exhausted-p twice)
                      "zero remaining is exhausted")
        (handler-case
            (progn
              (hackmode:expert-budget-consume
               twice "provider-actions" :amount 1)
              (error "over-budget consume unexpectedly succeeded"))
          (hackmode:expert-budget-denied () t))))
    (handler-case
        (progn
          (hackmode:expert-budget-consume state "unknown" :amount 1)
          (error "unknown budget unexpectedly succeeded"))
      (hackmode:invalid-expert-budget () t))
    (handler-case
        (progn
          (hackmode:make-expert-budget-state
           objective :operation "" :run-id "run-1")
          (error "empty operation unexpectedly succeeded"))
      (hackmode:invalid-expert-budget () t))
    t))
