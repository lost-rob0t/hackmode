(in-package :hackmode-database-tests)

(defun run-visual-evidence-tests ()
  (let* ((first (hackmode-database:make-visual-evidence-record
                 :operation-id "op-visual"
                 :run-id "run-1"
                 :job-id "shot-1"
                 :asset-id "url:https://example.test/"
                 :requested-url "https://example.test/"
                 :final-url "https://example.test/login"
                 :screenshot-evidence-ref "evidence/screens/shot-1.png"
                 :screenshot-digest "sha256:shot"
                 :captured-at "2026-08-31T19:00:00Z"
                 :title "Fixture"
                 :http-status 200
                 :viewport '(:width 1280 :height 720)
                 :client-profile-id "chromium-fixture/1"
                 :browser-id "chromium"
                 :browser-version "fixture"
                 :duration-ms 25
                 :body-digest "sha256:body"
                 :technology-hints '("nginx" "fixture")
                 :capture-session-id "capture-1"
                 :exchange-id "exchange-1"
                 :provenance '(:provider "visual-fixture/1")))
         (same (hackmode-database:make-visual-evidence-record
                :operation-id "op-visual"
                :run-id "run-1"
                :job-id "shot-1"
                :asset-id "url:https://example.test/"
                :requested-url "https://example.test/"
                :final-url "https://example.test/login"
                :screenshot-evidence-ref "evidence/screens/shot-1.png"
                :screenshot-digest "sha256:shot"
                :captured-at "2026-08-31T19:00:00Z"
                :title "Fixture"
                :http-status 200
                :viewport '(:width 1280 :height 720)
                :client-profile-id "chromium-fixture/1"
                :browser-id "chromium"
                :browser-version "fixture"
                :duration-ms 25
                :body-digest "sha256:body"
                :technology-hints '("nginx" "fixture")
                :capture-session-id "capture-1"
                :exchange-id "exchange-1"
                :provenance '(:provider "visual-fixture/1"))))
    (ensure (string= (hackmode-database:visual-evidence-record-record-id first)
                     (hackmode-database:visual-evidence-record-record-id same))
            "visual evidence replay changed stable identity")
    (ensure (string= "capture-1"
                     (hackmode-database:visual-evidence-record-capture-session-id first))
            "capture session correlation was not retained")
    (ensure (string= "exchange-1"
                     (hackmode-database:visual-evidence-record-exchange-id first))
            "HTTP exchange correlation was not retained")
    (let* ((path (merge-pathnames
                  (format nil "hackmode-visual-evidence-~D/" (random 1000000000))
                  (uiop:temporary-directory)))
           (database (tek9:new-database "hackmode-visual-evidence-test" :path path)))
      (unwind-protect
           (progn
             (tek9:open-database database)
             (hackmode-database:persist-visual-evidence-record database first)
             (hackmode-database:persist-visual-evidence-record database same)
             (let ((records (hackmode-database:fetch-visual-evidence-records
                             database "op-visual" :run-id "run-1")))
               (ensure (= 1 (length records))
                       "visual evidence replay duplicated canonical state")
               (ensure (equal (tek9:node-props
                               (hackmode-database:visual-evidence-record->tek9-node first))
                              (tek9:node-props
                               (hackmode-database:visual-evidence-record->tek9-node
                                (first records))))
                       "visual evidence changed during Tek9 round-trip")
               (ensure (string=
                        (hackmode-database:visual-evidence-record-record-id first)
                        (hackmode-database:visual-evidence-record-record-id
                         (hackmode-database:fetch-visual-evidence-record
                          database "op-visual"
                          (hackmode-database:visual-evidence-record-record-id first))))
                       "singular visual evidence fetch lost stable identity"))
             (handler-case
                 (progn
                   (hackmode-database:persist-visual-evidence-record
                    database
                    (hackmode-database:make-visual-evidence-record
                     :operation-id "op-visual"
                     :run-id "run-1"
                     :job-id "shot-1"
                     :asset-id "url:https://example.test/"
                     :requested-url "https://example.test/"
                     :final-url "https://example.test/login"
                     :screenshot-evidence-ref "evidence/screens/shot-1.png"
                     :screenshot-digest "sha256:different"
                     :captured-at "2026-08-31T19:00:00Z"
                     :duration-ms 25
                     :provenance '(:provider "visual-fixture/1")))
                   (error "divergent visual replay unexpectedly accepted"))
               (hackmode-database:persistence-replay-conflict () t)))
        (when (tek9:db-is-open-p database)
          (tek9:close-database database))
        (when (probe-file path)
          (uiop:delete-directory-tree path :validate t))))
    (handler-case
        (progn
          (hackmode-database:make-visual-evidence-record
           :operation-id "op-visual"
           :run-id "run-1"
           :job-id "missing-ref"
           :asset-id "url:https://example.test/"
           :requested-url "https://example.test/"
           :final-url "https://example.test/"
           :screenshot-evidence-ref nil
           :screenshot-digest "sha256:shot"
           :captured-at "2026-08-31T19:00:00Z"
           :duration-ms 1
           :provenance '(:provider "visual-fixture/1"))
          (error "missing screenshot evidence reference unexpectedly accepted"))
      (hackmode-database:execution-graph-validation-error () t)))
  t)