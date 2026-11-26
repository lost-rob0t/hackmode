(spec-library "org.hackmode/system@1"
  (:version "1.0.0")

  (scalar rate-limit-id
    (:base string
     :pattern "^[a-zA-Z0-9][a-zA-Z0-9._:-]{2,127}$"))

  (scalar request-quota
    (:base integer
     :minimum 1))

  (scalar window-seconds
    (:base integer
     :minimum 1))

  (enum egress-kind
    (direct proxy-list rotating-tor))

  (document max-rate-limit
    (:persistence persistent)
    (policyId rate-limit-id :required)
    (maxPerHost request-quota :required)
    (maxPerIp request-quota :required)
    (windowSeconds window-seconds :required)
    (egress egress-kind :optional :default direct))

  (message declare-rate-limit
    (:fields
     ((policyId rate-limit-id :required)
      (maxPerHost request-quota :required)
      (maxPerIp request-quota :required)
      (windowSeconds window-seconds :required)
      (egress egress-kind :optional)))))
