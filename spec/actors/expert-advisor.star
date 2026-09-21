(actor expert-advisor
  (:runtime native
   :service-uri "star://hackmode:localhost:expert-advisor"
   :accepts (hackmode/classify-target@1 hackmode/recommend-capabilities@1)
   :produces (hackmode/expert-recommendation@1)
   :handler hackmode-actor-expert-advisor
   :restart temporary
   :mailbox (bounded 64)
   :metadata ((domain "hackmode") (role "advisory-reasoning"))))
