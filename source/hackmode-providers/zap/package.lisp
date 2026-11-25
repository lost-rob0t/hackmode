(defpackage :hackmode-provider-zap
  (:use :cl)
  (:nicknames :hackmode.providers.zap)
  (:export
   :*zap-url*
   :*zap-api-key-file*
   :*zap-scan-poll-seconds*
   :zap-url
   :zap-api-key
   :zap-get
   :zap-call
   :zap-error
   :zap-error-message
   :zap-error-body
   :zap-error-stderr
   :percent-encode
   :run-zap-plugin
   :zap-plugin-pathname
   :zap-plugin-names
   :run-zap-scan
   :zap-scan-findings
   :alerts-to-findings
   :run-zap-plugin-probe
   :zap-plugin-finding
   :run-race-probe
   :run-smuggle-probe
   :run-jwt-toolkit
   :run-param-miner
   :run-authz-diff
   :run-content-discovery
   :run-graphql-probe
   :register-zap-providers))

(in-package :hackmode-provider-zap)
