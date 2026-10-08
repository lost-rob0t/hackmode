(actor outbox
  (:runtime native
   :service-uri "star://hackmode:localhost:outbox"
   :accepts (hackmode/enqueue-document@1 hackmode/drain-outbox@1)
   :produces (hackmode/outbox-state@1)
   :handler hackmode-actor-outbox
   :restart permanent
   :mailbox (bounded 512)
   :metadata ((domain "hackmode") (role "ingest-starintel"))))
