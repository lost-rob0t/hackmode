(actor asset-monitor
  (:runtime native
   :service-uri "star://hackmode:localhost:asset-monitor"
   :accepts (hackmode/asset-discovered@1)
   :produces (hackmode/enqueue-document@1)
   :handler hackmode-actor-asset-monitor
   :restart permanent
   :mailbox (bounded 256)
   :metadata ((domain "hackmode") (role "project-assets"))))
