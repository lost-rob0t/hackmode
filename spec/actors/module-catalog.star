(actor module-catalog
  (:runtime native
   :service-uri "star://hackmode:localhost:module-catalog"
   :accepts (hackmode/module-families-request@1
             hackmode/module-list-request@1
             hackmode/module-describe-request@1)
   :produces (hackmode/module-catalog-result@1)
   :handler hackmode-actor-module-catalog
   :restart transient
   :mailbox (bounded 128)
   :metadata ((domain "hackmode") (role "module-catalog") (projection "summary"))))
