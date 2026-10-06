(defpackage :hackmode-modules
  (:use :cl)
  (:documentation "Dependency-free, in-process module catalog and instance descriptions.")
  (:export
   :module-validation-error :module-error-field :module-error-reason
   :module-option :make-module-option :module-option-info
   :module-descriptor :make-module-descriptor :module-info
   :module-registry :make-module-registry :*module-registry*
   :register-module :unregister-module :find-module :list-modules
   :list-module-families :module-payload-compatible-p
   :module-instance :instantiate-module :module-instance-info
   :module-catalog-request :make-module-catalog-request
   :module-catalog-result :module-catalog-result-info
   :handle-module-catalog-request :make-module-catalog-receiver))
