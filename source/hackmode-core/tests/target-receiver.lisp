(in-package :hackmode-tests)

(defun make-target-document (actor target target-type
                             &key
                               (id "target-1")
                               (dataset "inventory-2026-09-17")
                               capability
                               provider
                               operation
                               (execution-id "execution-1"))
  (let ((extension (jsown:empty-object))
        (extensions (jsown:empty-object)))
    (when capability
      (setf (jsown:val extension "capability") capability))
    (when provider
      (setf (jsown:val extension "provider") provider))
    (when operation
      (setf (jsown:val extension "operation") operation))
    (when (or capability provider operation)
      (setf (jsown:val extensions hackmode:*starintel-target-extension-key*)
            extension))
    (when execution-id
      (setf (jsown:val extensions "target_execution_id") execution-id))
    (jsown:new-js
      ("_id" id)
      ("dataset" dataset)
      ("dtype" "target")
      ("schema_version" "0.9.0")
      ("extensions" extensions)
      ("data"
       (jsown:new-js
         ("actor" actor)
         ("target" target)
         ("target_type" target-type))))))

(defun run-fixed-target-receiver-test ()
  (let* ((definition
           (hackmode::make-target-receiver-definition
            :actor-name "hackmode.dns-resolve.massdns"
            :capability "dns-resolve"
            :provider "massdns"
            :input-type 'hackmode:domain))
         (document
           (make-target-document
            "hackmode.dns-resolve.massdns"
            "Example.COM."
            "domain"
            :operation "op-17"))
         (request
           (hackmode:starintel-target->dispatch-request document definition))
         (input (hackmode:target-dispatch-request-input request)))
    (assert-equal "dns-resolve"
                  (hackmode:target-dispatch-request-capability request)
                  "fixed capability")
    (assert-equal "massdns"
                  (hackmode:target-dispatch-request-provider request)
                  "fixed provider")
    (assert-equal "inventory-2026-09-17"
                  (hackmode:target-dispatch-request-dataset request)
                  "target dataset")
    (assert-equal "execution-1"
                  (hackmode:target-dispatch-request-execution-id request)
                  "execution identity")
    (assert (typep input 'hackmode:domain))
    (assert-equal "example.com"
                  (hackmode:domain-name input)
                  "normalized target domain")
    (assert-equal "op-17" (hackmode:doc-operation input) "operation context")
    (assert (member "dataset:inventory-2026-09-17"
                    (hackmode:doc-tags input)
                    :test #'string=))
    (assert (member "target:target-1"
                    (hackmode:doc-tags input)
                    :test #'string=))
    (assert (member "execution:execution-1"
                    (hackmode:doc-tags input)
                    :test #'string=))))

(defun run-generic-target-receiver-test ()
  (let* ((definition (hackmode:generic-target-definition))
         (document
           (make-target-document
            "hackmode"
            "198.51.100.44"
            "ip"
            :capability "service-scan"
            :provider "scanner"))
         (request
           (hackmode:starintel-target->dispatch-request document definition))
         (input (hackmode:target-dispatch-request-input request)))
    (assert-equal "service-scan"
                  (hackmode:target-dispatch-request-capability request)
                  "generic capability")
    (assert-equal "scanner"
                  (hackmode:target-dispatch-request-provider request)
                  "generic provider")
    (assert (typep input 'hackmode:host))
    (assert-equal "198.51.100.44" (hackmode:doc-ip input) "host IP")))

(defun run-target-receiver-dispatch-test ()
  (let* ((definition
           (hackmode::make-target-receiver-definition
            :actor-name "hackmode.web-probe.http"
            :capability "web-probe"
            :provider "http"
            :input-type 'hackmode:url))
         (document
           (make-target-document
            "hackmode.web-probe.http"
            "https://example.test:8443/a/b?q=1"
            "url"))
         (seen nil)
         (handler
           (hackmode:target-receiver-handler
            definition
            :dispatch-fn
            (lambda (capability input &key provider)
              (setf seen (list capability input provider))
              :queued))))
    (assert (eq :queued (funcall handler document)))
    (assert-equal "web-probe" (first seen) "dispatched capability")
    (assert (typep (second seen) 'hackmode:url))
    (assert-equal "example.test"
                  (hackmode:url-host (second seen))
                  "dispatched URL host")
    (assert-equal 8443 (hackmode:url-port (second seen)) "dispatched URL port")
    (assert-equal "http" (third seen) "dispatched provider")))

(defun run-provider-target-name-test ()
  (unwind-protect
       (progn
         (hackmode:clear-capability-providers)
         (hackmode:register-capability-provider
          "DNS Resolve"
          "Mass DNS"
          (lambda (input) input)
          :input-type 'hackmode:domain
          :output-types '(hackmode:host))
         (let* ((provider (first (hackmode:list-capability-providers)))
                (definition (hackmode:provider-target-definition provider)))
           (assert-equal "hackmode.dns-resolve.mass-dns"
                         (hackmode:target-receiver-definition-actor-name definition)
                         "provider target actor name")))
    (hackmode:clear-capability-providers)))

(defun run-target-actor-mismatch-test ()
  (let ((definition
          (hackmode::make-target-receiver-definition
           :actor-name "hackmode.expected"
           :capability "test"
           :provider nil
           :input-type nil))
        (document (make-target-document "hackmode.other" "x" "string")))
    (handler-case
        (progn
          (hackmode:starintel-target->dispatch-request document definition)
          (error "Expected mismatched target actor to fail."))
      (error (condition)
        (assert (search "does not match" (princ-to-string condition)))))))

(defun run-target-receiver-tests ()
  (run-fixed-target-receiver-test)
  (run-generic-target-receiver-test)
  (run-target-receiver-dispatch-test)
  (run-provider-target-name-test)
  (run-target-actor-mismatch-test)
  t)
