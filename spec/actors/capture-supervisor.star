(actor capture-supervisor
  (:runtime native
   :service-uri "star://hackmode:localhost:capture-supervisor"
   :accepts (hackmode/start-capture@1 hackmode/stop-capture@1)
   :produces (hackmode/capture-state@1)
   :handler hackmode-actor-capture-supervisor
   :restart permanent
   :mailbox (bounded 64)
   :metadata ((domain "hackmode") (role "manage-traffic-capture"))))
