(defpackage :hackmode-module-actor-tests
  (:use :cl)
  (:export :run-module-actor-tests))

(in-package :hackmode-module-actor-tests)

(defun await-result (function)
  (let ((deadline (+ (get-internal-real-time)
                     (* 5 internal-time-units-per-second))))
    (loop for result = (funcall function)
          when result return result
          when (>= (get-internal-real-time) deadline)
            do (error "Timed out waiting for catalog actor result.")
          do (sleep 0.01))))

(defun run-module-actor-tests ()
  ;; Bad registry arguments must not allocate a shared runtime or start threads.
  (let ((hackmode:*hackmode-actor-system* nil)
        (hackmode:*outbox-actor* nil)
        (hackmode:*provider-supervisor* nil))
    (unwind-protect
         (progn
           (assert
            (handler-case
                (progn (hackmode:start-module-catalog-actor :registry :invalid) nil)
              (hackmode-modules:module-validation-error () t)))
           (assert (null hackmode:*hackmode-actor-system*)))
      (when hackmode:*hackmode-actor-system*
        (hackmode:stop-hackmode-actor-system))))

  ;; Exercise actual Sento message delivery, including the explicit async reply.
  (let ((hackmode:*hackmode-actor-system* nil)
        (hackmode:*outbox-actor* nil)
        (hackmode:*provider-supervisor* nil)
        (registry (hackmode-modules:make-module-registry)))
    (unwind-protect
         (let* ((descriptor
                  (hackmode-modules:make-module-descriptor
                   :id "recon/catalog-smoke" :version "1" :family :recon))
                (registered (hackmode-modules:register-module descriptor :registry registry))
                (actor (hackmode:start-module-catalog-actor :registry registry))
                (second-actor (hackmode:start-module-catalog-actor :registry registry))
                (request
                  (hackmode-modules:make-module-catalog-request
                   :request-id "native-1" :operation-id "operation-1"
                   :command :describe :id "recon/catalog-smoke" :version "1"))
                (expected
                  (hackmode-modules:module-catalog-result-info
                   (hackmode-modules:handle-module-catalog-request request :registry registry))))
           (declare (ignore registered))
           (assert hackmode:*hackmode-actor-system*)
           (assert (not (eq actor second-actor)))
           (assert (equal expected
                          (hackmode-modules:module-catalog-result-info
                           (sento.actor:ask-s actor request :time-out 5))))
           (let* ((future (sento.actor:ask actor request :time-out 5))
                  (result
                    (await-result
                     (lambda ()
                       (when (sento.future:complete-p future)
                         (sento.future:fresult future))))))
             (assert (equal expected (hackmode-modules:module-catalog-result-info result))))
           (let ((last-result nil))
             (let ((probe
                     (sento.actor-context:actor-of
                      hackmode:*hackmode-actor-system*
                      :name "module-catalog-reply-probe" :dispatcher :providers
                      :receive (lambda (message)
                                 (if (eq message :peek)
                                     last-result
                                     (setf last-result message))))))
               (sento.actor:tell actor request probe)
               (let ((result (await-result
                              (lambda () (sento.actor:ask-s probe :peek :time-out 5)))))
                 (assert (equal expected
                                (hackmode-modules:module-catalog-result-info result)))))))
      (when hackmode:*hackmode-actor-system*
        (hackmode:stop-hackmode-actor-system))))

  ;; Selection must preserve the legacy API and must not execute either function.
  (let* ((hackmode:*current-exploit* nil)
         (selected
           (make-instance 'hackmode:exploit :name "selection-only" :platform "local"
                          :func (lambda () (error "Selection executed a function."))
                          :exploit-setup (lambda () (error "Selection executed setup.")))))
    (assert (eq selected (hackmode:use selected)))
    (assert (eq selected hackmode:*current-exploit*)))
  t)
