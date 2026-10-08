(actor replay
  (:runtime native
   :service-uri "star://hackmode:localhost:replay"
   :accepts (hackmode/replay-spool@1)
   :produces (hackmode/enqueue-document@1)
   :handler hackmode-actor-replay
   :restart transient
   :mailbox (bounded 64)
   :metadata ((domain "hackmode") (role "fold-spool-evidence"))))
