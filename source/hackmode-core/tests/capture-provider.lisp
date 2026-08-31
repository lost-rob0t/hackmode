(in-package :hackmode-tests)

(defun run-capture-provider-tests ()
  (let ((launches 0)
        (stops 0)
        (seen-specs nil)
        (hackmode:*db* nil))
    (flet ((runner (spec)
             (incf launches)
             (push spec seen-specs)
             (format nil "pid-~d" launches))
           (stopper (process-id)
             (declare (ignore process-id))
             (incf stops)
             t))
      (let* ((service
               (hackmode:start-capture-service
                "op-135"
                :capture-session-id "capture-135"
                :endpoint "http://127.0.0.1:18080"
                :spool-id "spool-135"
                :spool-path "/tmp/op-135.ipx.jsonl"
                :max-restarts 1
                :runner #'runner
                :stopper #'stopper))
             (initial-session
               (hackmode:capture-service-capture-session-id service)))
        (assert-equal :running
                      (hackmode:capture-service-state service)
                      "capture running state")
        (assert-equal "op-135"
                      (hackmode:capture-service-operation-id service)
                      "capture operation scope")
        (assert-equal "capture-135"
                      initial-session
                      "capture session identity")
        (assert-equal "http://127.0.0.1:18080"
                      (hackmode:capture-service-endpoint service)
                      "capture endpoint")
        (assert-equal "spool-135"
                      (hackmode:capture-service-spool-id service)
                      "capture spool identity")
        (assert-equal "pid-1"
                      (hackmode:capture-service-process-id service)
                      "first process identity")
        (assert-equal 1 launches "initial launch count")
        (assert (null hackmode:*db*) ()
                "Capture lifecycle must not require or mutate Tek9 state.")

        (hackmode:note-capture-process-exit service :exit-code 23)
        (assert-equal :running
                      (hackmode:capture-service-state service)
                      "capture restarted state")
        (assert-equal initial-session
                      (hackmode:capture-service-capture-session-id service)
                      "stable capture session across restart")
        (assert-equal 1
                      (hackmode:capture-service-restart-count service)
                      "restart count")
        (assert-equal "pid-2"
                      (hackmode:capture-service-process-id service)
                      "replacement process identity")
        (assert-equal 2 launches "restart launch count")

        (hackmode:stop-capture-service service)
        (assert-equal :stopped
                      (hackmode:capture-service-state service)
                      "explicit stop state")
        (assert-equal 1 stops "stopper invocation count")
        (assert-equal 2 launches "stop does not relaunch")
        (assert (= 2 (length seen-specs)) ()
                "Each launch must receive an explicit typed capture specification.")
        (let ((spec (first seen-specs)))
          (assert-equal "op-135"
                        (hackmode:capture-process-spec-operation-id spec)
                        "process spec operation")
          (assert-equal "capture-135"
                        (hackmode:capture-process-spec-capture-session-id spec)
                        "process spec capture session")
          (assert-equal "/tmp/op-135.ipx.jsonl"
                        (hackmode:capture-process-spec-spool-path spec)
                        "process spec spool path")
          (assert-equal '("--listen-host" "127.0.0.1"
                          "--listen-port" "18080"
                          "-s" "tools/ipx/mitmproxy-addon.py"
                          "--set" "hackmode_operation_id=op-135"
                          "--set" "hackmode_capture_session_id=capture-135"
                          "--set" "hackmode_spool_id=spool-135"
                          "--set" "hackmode_spool_path=/tmp/op-135.ipx.jsonl"
                          "--set" "hackmode_ipx_version=1")
                        (hackmode:capture-process-spec-arguments spec)
                        "mitmdump IPX addon arguments"))))

    (let ((exhaust-launches 0))
      (flet ((runner (spec)
               (declare (ignore spec))
               (incf exhaust-launches)
               (format nil "exhaust-pid-~d" exhaust-launches)))
        (let ((service
                (hackmode:start-capture-service
                 "op-exhaust"
                 :capture-session-id "capture-exhaust"
                 :endpoint "http://127.0.0.1:18082"
                 :spool-id "spool-exhaust"
                 :max-restarts 1
                 :runner #'runner)))
          (hackmode:note-capture-process-exit service :exit-code 23)
          (hackmode:note-capture-process-exit service :exit-code 24)
          (assert-equal :failed
                        (hackmode:capture-service-state service)
                        "restart exhaustion state")
          (assert-equal :restart-exhausted
                        (hackmode:capture-service-failure-class service)
                        "restart exhaustion classification")
          (assert-equal 2 exhaust-launches "bounded restart count")
          (assert-equal "capture-exhaust"
                        (hackmode:capture-service-capture-session-id service)
                        "session remains stable after exhaustion")))))

  (let ((hackmode:*db* nil))
    (flet ((failing-runner (spec)
             (declare (ignore spec))
             (error "fixture spawn failure")))
      (let ((service
              (hackmode:start-capture-service
               "op-fail"
               :capture-session-id "capture-fail"
               :endpoint "http://127.0.0.1:18081"
               :spool-id "spool-fail"
               :runner #'failing-runner)))
        (assert-equal :failed
                      (hackmode:capture-service-state service)
                      "spawn failure state")
        (assert-equal :spawn-failed
                      (hackmode:capture-service-failure-class service)
                      "spawn failure classification")
        (assert (search "fixture spawn failure"
                        (or (hackmode:capture-service-last-error service) "")) ()
                "Spawn failures must remain inspectable without escaping into the operation runtime."))))
  t)
