(in-package :hackmode)

(defvar *api-common-patterns* (list "/api/" "/v1/" "/v2/" "/rest/" "/rest/v1/" "/rest/v2/" "/rpc/" "/rpc/v1/" "/rpc/v2/"
                                    "/services/" "/services/api/" "/services/v1/" "/services/v2/" "/public/api/"
                                    "/public/v1/" "/public/v2/" "/app/api/" "/app/v1/" "/app/v2/" "/api/v1/"
                                    "/api/v2/" "/api/rest/" "/api/rest/v1/" "/api/rest/v2/" "/api/rpc/" "/api/rpc/v1/"
                                    "/api/rpc/v2/" "/api/services/" "/api/services/v1/" "/api/services/v2/"
                                    "/api/public/" "/api/public/v1/" "/api/public/v2/" "/api/app/" "/api/app/v1/"
                                    "/api/app/v2/" "/restful/" "/restful/v1/" "/restful/v2/" "/rest/v1/endpoints/"
                                    "/rest/v2/endpoints/" "/graphql/" "/graphql/v1/" "/graphql/v2/" "/v1/endpoints/"
                                    "/v2/endpoints/" "/public/v1/endpoints/" "/public/v2/endpoints/" "/app/v1/endpoints/"
                                    "/app/v2/endpoints/" "/api/v1/endpoints/" "/api/v2/endpoints/" "/restful/endpoints/"
                                    "/restful/v1/endpoints/" "/restful/v2/endpoints/" "/rest/v1/methods/" "/rest/v2/methods/"
                                    "/graphql/methods/" "/v1/methods/" "/v2/methods/" "/public/v1/methods/" "/public/v2/methods/"
                                    "/app/v1/methods/" "/app/v2/methods/" "/api/v1/methods/" "/api/v2/methods/"
                                    "/restful/methods/" "/restful/v1/methods/" "/restful/v2/methods/" "/rest/methods/"
                                    "/rest/v1/actions/" "/rest/v2/actions/" "/graphql/actions/" "/v1/actions/"
                                    "/v2/actions/" "/public/v1/actions/" "/public/v2/actions/" "/app/v1/actions/"
                                    "/app/v2/actions/" "/api/v1/actions/" "/api/v2/actions/" "/restful/actions/"
                                    "/restful/v1/actions/" "/restful/v2/actions/" "/rest/actions/" "/rest/v1/tasks/"
                                    "/rest/v2/tasks/" "/graphql/tasks/" "/v1/tasks/" "/v2/tasks/" "/public/v1/tasks/"
                                    "/public/v2/tasks/" "/app/v1/tasks/" "/app/v2/tasks/" "/api/v1/tasks/" "/api/v2/tasks/"
                                    "/restful/tasks/" "/restful/v1/tasks/" "/restful/v2/tasks/" "/rest/tasks/"))

(defun find-api (url-object &optional (patterns *api-common-patterns*))
  "find api urls based on the given pattern in the :path field of the url-object.
   adds 'api' tag to the url-object if it matches the pattern."
  (let ((path (url-path url-object)))
    (car  (loop for pattern in patterns
                if  (and path (cl-ppcre:scan pattern path))
                  collect (progn (setf (doc-tags url-object) (push "api" (doc-tags url-object)))
                                 url-object)))))

(defun find-apis (url-objects &optional (common-api-urls *api-common-patterns*))
  "find api urls in a list of url-objects based on the given pattern.
   adds 'api' tag to each url-object if it matches the pattern."
  (mapcar (lambda (url-object) (find-api pattern url-object common-api-urls)) url-objects))
