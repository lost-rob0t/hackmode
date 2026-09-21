(actor provider-dispatcher
  (:runtime native
   :service-uri "star://hackmode:localhost:provider-dispatcher"
   :accepts (hackmode/run-capability@1)
   :produces (hackmode/provider-result@1 hackmode/asset-discovered@1)
   :handler hackmode-actor-provider-dispatcher
   :restart transient
   :mailbox (bounded 128)
   :metadata ((domain "hackmode") (role "run-capabilities"))))
