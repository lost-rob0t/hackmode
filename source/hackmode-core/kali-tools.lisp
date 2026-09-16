(in-package :hackmode)

(defun tool-command-target-string (input)
  "Return INPUT's validated target as an argv-safe string value."
  (let ((target (tool-command-input-target input)))
    (typecase target
      (domain (domain-name target))
      (host (asset-canonical-value target))
      (url (asset-canonical-value target))
      (string target)
      (t (princ-to-string target)))))

(defun argument-value->string (value)
  (etypecase value
    (string value)
    (integer (princ-to-string value))
    (real (princ-to-string value))
    (symbol (string-downcase (symbol-name value)))))

(defun tool-argument-value-argv (definition value)
  (let ((flag (tool-argument-flag definition)))
    (cond
      ((eq (tool-argument-type definition) 'boolean)
       (if value
           (if flag (list flag) nil)
           nil))
      ((tool-argument-repeatable-p definition)
       (loop for item in value
             append (if flag
                        (list flag (argument-value->string item))
                        (list (argument-value->string item)))))
      (flag
       (list flag (argument-value->string value)))
      (t
       (list (argument-value->string value))))))

(defun declared-arguments->argv (definitions values)
  (loop for definition in definitions
        for name = (tool-argument-name definition)
        when (plist-key-present-p values name)
          append (tool-argument-value-argv
                  definition
                  (getf values name))))

(defun instantiate-tool-fixed-arguments (fixed target)
  (let ((used-target-p nil))
    (values
     (loop for item in fixed
           collect
           (if (string= item "{target}")
               (progn
                 (setf used-target-p t)
                 target)
               item))
     used-target-p)))

(defun build-tool-command-argv (mapping input)
  "Build a shell-free argv list from MAPPING and validated INPUT."
  (let* ((program (tool-mapping-executable mapping))
         (target (tool-command-target-string input))
         (shape
           (or (find-tool-target-shape
                (tool-command-input-target-shape input))
               (error "Unknown validated target shape ~a."
                      (tool-command-input-target-shape input))))
         (argument-argv
           (declared-arguments->argv
            (tool-mapping-arguments mapping)
            (tool-command-input-arguments input)))
         (target-option-argv
           (declared-arguments->argv
            (tool-target-shape-options shape)
            (tool-command-input-target-options input))))
    (unless (and program (plusp (length program)))
      (error "Tool mapping ~a/~a has no executable."
             (tool-mapping-capability mapping)
             (tool-mapping-provider mapping)))
    (multiple-value-bind (fixed used-target-p)
        (instantiate-tool-fixed-arguments
         (tool-mapping-fixed-arguments mapping)
         target)
      (append
       (list program)
       fixed
       argument-argv
       target-option-argv
       (unless used-target-p (list target))))))

(defun tool-process-evidence (mapping input stdout stderr exit-code argv)
  (jsown:to-json
   (jsown:new-js
    ("tool" (tool-mapping-provider mapping))
    ("capability" (tool-mapping-capability mapping))
    ("targetShape" (tool-command-input-target-shape input))
    ("target" (tool-command-target-string input))
    ("argv" (copy-list argv))
    ("arguments" (with-standard-io-syntax
                     (prin1-to-string
                      (tool-command-input-arguments input))))
    ("targetOptions" (with-standard-io-syntax
                         (prin1-to-string
                          (tool-command-input-target-options input))))
    ("exitCode" (or exit-code 0))
    ("stdout" (or stdout ""))
    ("stderr" (or stderr "")))))

(defun run-command-tool (capability provider input)
  "Execute a declared command tool with argv isolation and return exact evidence."
  (check-type input tool-command-input)
  (let ((mapping
          (or (find-tool-mapping capability provider)
              (error "No tool mapping for ~a/~a." capability provider))))
    (unless (tool-mapping-available-p mapping)
      (error "Tool executable ~a is unavailable."
             (tool-mapping-executable mapping)))
    (let ((argv (build-tool-command-argv mapping input)))
      (multiple-value-bind (stdout stderr exit-code)
          (uiop:run-program
           argv
           :output :string
           :error-output :string
           :ignore-error-status t)
        (list
         (make-instance
          'finding
          :document-id (provider-input-id (tool-command-input-target input))
          :finding-type "tool-output"
          :data (tool-process-evidence
                 mapping input stdout stderr exit-code argv)
          :tool (tool-mapping-provider mapping)
          :tags (list "tool-output"
                      (tool-mapping-capability mapping)
                      (tool-mapping-provider mapping))))))))

(defun ensure-command-tool-provider (capability provider &key (priority 100))
  "Install the generic argv-based provider unless a provider already owns the key."
  (or (find-capability-provider capability provider)
      (register-capability-provider
       capability
       provider
       (lambda (input)
         (run-command-tool capability provider input))
       :input-type 'tool-command-input
       :output-types '(finding)
       :priority priority)))

(defun kali-package (name)
  (list (cons "kali" name)))

(defun common-scan-arguments ()
  (list
   (make-tool-arg :timeout 'integer
                  :flag "--timeout"
                  :description "Tool-specific timeout value when supported.")))

(define-tool-mapping (:network-scan :nmap)
  :executable "nmap"
  :target-shapes '(host network domain)
  :arguments
  (list
   (make-tool-arg :ports 'string :flag "-p"
                  :description "Port expression, for example 22,80,443 or 1-1024.")
   (make-tool-arg :service-version 'boolean :flag "-sV" :default t
                  :description "Enable service/version detection.")
   (make-tool-arg :os-detection 'boolean :flag "-O"
                  :description "Enable OS detection when privileges permit."))
  :fixed-arguments '("-oX" "-" "{target}")
  :example-targets '("192.0.2.10" "192.0.2.0/24" "example.org")
  :platforms '("kali" "linux")
  :packages (kali-package "nmap")
  :metadata '(:category "network" :mode "assessment"))

(define-tool-mapping (:port-scan :masscan)
  :executable "masscan"
  :target-shapes '(host network)
  :arguments
  (list
   (make-tool-arg :ports 'string :flag "-p" :default "1-1000")
   (make-tool-arg :rate 'integer :flag "--rate" :default 1000))
  :fixed-arguments '("--output-format" "json" "--output-filename" "-" "{target}")
  :example-targets '("192.0.2.0/24")
  :platforms '("kali" "linux")
  :packages (kali-package "masscan")
  :metadata '(:category "network" :mode "assessment"))

(define-tool-mapping (:port-scan :rustscan)
  :executable "rustscan"
  :target-shapes '(host)
  :arguments
  (list
   (make-tool-arg :ports 'string :flag "-p")
   (make-tool-arg :batch-size 'integer :flag "--batch-size"))
  :fixed-arguments '("--addresses" "{target}" "--greppable")
  :example-targets '("192.0.2.10")
  :platforms '("kali" "linux")
  :packages (kali-package "rustscan")
  :metadata '(:category "network" :mode "assessment"))

(define-tool-mapping (:port-scan :naabu)
  :executable "naabu"
  :target-shapes '(host domain)
  :arguments
  (list
   (make-tool-arg :ports 'string :flag "-p")
   (make-tool-arg :rate 'integer :flag "-rate"))
  :fixed-arguments '("-silent" "-json" "-host" "{target}")
  :example-targets '("example.org" "192.0.2.10")
  :platforms '("kali" "linux")
  :packages (kali-package "naabu")
  :metadata '(:category "network" :mode "assessment"))

(define-tool-mapping (:subdomain-enumerate :subfinder)
  :executable "subfinder"
  :target-shapes '(domain)
  :fixed-arguments '("-silent" "-d" "{target}")
  :example-targets '("example.org")
  :platforms '("kali" "linux")
  :packages (kali-package "subfinder")
  :metadata '(:category "dns" :mode "discovery"))

(define-tool-mapping (:subdomain-enumerate :amass)
  :executable "amass"
  :target-shapes '(domain)
  :arguments
  (list (make-tool-arg :passive 'boolean :flag "-passive" :default t))
  :fixed-arguments '("enum" "-d" "{target}")
  :example-targets '("example.org")
  :platforms '("kali" "linux")
  :packages (kali-package "amass")
  :metadata '(:category "dns" :mode "discovery"))

(define-tool-mapping (:dns-resolve :dnsx)
  :executable "dnsx"
  :target-shapes '(domain)
  :arguments
  (list
   (make-tool-arg :a 'boolean :flag "-a" :default t)
   (make-tool-arg :aaaa 'boolean :flag "-aaaa")
   (make-tool-arg :mx 'boolean :flag "-mx"))
  :fixed-arguments '("-silent" "-json" "-d" "{target}")
  :example-targets '("example.org")
  :platforms '("kali" "linux")
  :packages (kali-package "dnsx")
  :metadata '(:category "dns" :mode "discovery"))

(define-tool-mapping (:dns-enumerate :dnsrecon)
  :executable "dnsrecon"
  :target-shapes '(domain)
  :arguments
  (list (make-tool-arg :type 'string :flag "-t" :default "std"))
  :fixed-arguments '("-d" "{target}" "-j" "-")
  :example-targets '("example.org")
  :platforms '("kali" "linux")
  :packages (kali-package "dnsrecon")
  :metadata '(:category "dns" :mode "discovery"))

(define-tool-mapping (:http-probe :httpx)
  :executable "httpx"
  :target-shapes '(domain host url)
  :arguments
  (list
   (make-tool-arg :status-code 'boolean :flag "-status-code" :default t)
   (make-tool-arg :title 'boolean :flag "-title" :default t)
   (make-tool-arg :tech-detect 'boolean :flag "-tech-detect" :default t))
  :fixed-arguments '("-silent" "-json" "-u" "{target}")
  :example-targets '("https://example.org/" "example.org")
  :platforms '("kali" "linux")
  :packages (kali-package "httpx-toolkit")
  :metadata '(:category "web" :mode "discovery"))

(define-tool-mapping (:http-probe :curl)
  :executable "curl"
  :target-shapes '(url)
  :example-targets '("https://example.org/")
  :platforms '("kali" "linux")
  :packages (kali-package "curl")
  :metadata '(:category "web" :mode "discovery"))

(define-tool-mapping (:web-fingerprint :whatweb)
  :executable "whatweb"
  :target-shapes '(url domain host)
  :arguments
  (list (make-tool-arg :aggression 'integer :flag "-a" :default 1))
  :fixed-arguments '("--log-json=-" "{target}")
  :example-targets '("https://example.org/")
  :platforms '("kali" "linux")
  :packages (kali-package "whatweb")
  :metadata '(:category "web" :mode "fingerprint"))

(define-tool-mapping (:vulnerability-scan :nuclei)
  :executable "nuclei"
  :target-shapes '(url domain host)
  :arguments
  (list
   (make-tool-arg :tags 'string :flag "-tags")
   (make-tool-arg :severity 'string :flag "-severity")
   (make-tool-arg :rate-limit 'integer :flag "-rate-limit"))
  :fixed-arguments '("-silent" "-jsonl" "-u" "{target}")
  :example-targets '("https://example.org/")
  :platforms '("kali" "linux")
  :packages (kali-package "nuclei")
  :metadata '(:category "web" :mode "assessment"))

(define-tool-mapping (:web-scan :nikto)
  :executable "nikto"
  :target-shapes '(url domain host)
  :arguments
  (list (make-tool-arg :tuning 'string :flag "-Tuning"))
  :fixed-arguments '("-Format" "json" "-output" "-" "-h" "{target}")
  :example-targets '("https://example.org/")
  :platforms '("kali" "linux")
  :packages (kali-package "nikto")
  :metadata '(:category "web" :mode "assessment"))

(define-tool-mapping (:web-crawl :katana)
  :executable "katana"
  :target-shapes '(url)
  :arguments
  (list
   (make-tool-arg :depth 'integer :flag "-d" :default 3)
   (make-tool-arg :js-crawl 'boolean :flag "-jc"))
  :fixed-arguments '("-silent" "-jsonl" "-u" "{target}")
  :example-targets '("https://example.org/")
  :platforms '("kali" "linux")
  :packages (kali-package "katana")
  :metadata '(:category "web" :mode "discovery"))

(define-tool-mapping (:content-discovery :ffuf)
  :executable "ffuf"
  :target-shapes '(url)
  :arguments
  (list
   (make-tool-arg :wordlist 'string :flag "-w" :required t)
   (make-tool-arg :threads 'integer :flag "-t" :default 40)
   (make-tool-arg :match-codes 'string :flag "-mc"))
  :fixed-arguments '("-json" "-u" "{target}")
  :example-targets '("https://example.org/FUZZ")
  :platforms '("kali" "linux")
  :packages (kali-package "ffuf")
  :metadata '(:category "web" :mode "discovery"))

(define-tool-mapping (:content-discovery :feroxbuster)
  :executable "feroxbuster"
  :target-shapes '(url)
  :arguments
  (list
   (make-tool-arg :wordlist 'string :flag "-w")
   (make-tool-arg :threads 'integer :flag "-t" :default 50)
   (make-tool-arg :depth 'integer :flag "--depth"))
  :fixed-arguments '("--json" "-u" "{target}")
  :example-targets '("https://example.org/")
  :platforms '("kali" "linux")
  :packages (kali-package "feroxbuster")
  :metadata '(:category "web" :mode "discovery"))

(define-tool-mapping (:content-discovery :gobuster)
  :executable "gobuster"
  :target-shapes '(url)
  :arguments
  (list
   (make-tool-arg :wordlist 'string :flag "-w" :required t)
   (make-tool-arg :threads 'integer :flag "-t" :default 20))
  :fixed-arguments '("dir" "-q" "-u" "{target}")
  :example-targets '("https://example.org/")
  :platforms '("kali" "linux")
  :packages (kali-package "gobuster")
  :metadata '(:category "web" :mode "discovery"))

(define-tool-mapping (:content-discovery :dirsearch)
  :executable "dirsearch"
  :target-shapes '(url)
  :arguments
  (list
   (make-tool-arg :wordlist 'string :flag "-w")
   (make-tool-arg :threads 'integer :flag "-t" :default 25))
  :fixed-arguments '("--format" "json" "--url" "{target}")
  :example-targets '("https://example.org/")
  :platforms '("kali" "linux")
  :packages (kali-package "dirsearch")
  :metadata '(:category "web" :mode "discovery"))

(define-tool-mapping (:sql-assessment :sqlmap)
  :executable "sqlmap"
  :target-shapes '(url)
  :arguments
  (list
   (make-tool-arg :level 'integer :flag "--level")
   (make-tool-arg :risk 'integer :flag "--risk")
   (make-tool-arg :technique 'string :flag "--technique"))
  :fixed-arguments '("--batch" "--output-dir=/tmp/hackmode-sqlmap" "-u" "{target}")
  :example-targets '("https://example.org/item?id=1")
  :platforms '("kali" "linux")
  :packages (kali-package "sqlmap")
  :metadata '(:category "web" :mode "assessment"))

(define-tool-mapping (:tls-assessment :sslscan)
  :executable "sslscan"
  :target-shapes '(domain host)
  :fixed-arguments '("--xml=-" "{target}")
  :example-targets '("example.org" "192.0.2.10")
  :platforms '("kali" "linux")
  :packages (kali-package "sslscan")
  :metadata '(:category "tls" :mode "assessment"))

(define-tool-mapping (:smb-enumerate :enum4linux-ng)
  :executable "enum4linux-ng"
  :target-shapes '(host)
  :arguments
  (list (make-tool-arg :timeout 'integer :flag "-t"))
  :fixed-arguments '("-J" "-" "{target}")
  :example-targets '("192.0.2.10")
  :platforms '("kali" "linux")
  :packages (kali-package "enum4linux-ng")
  :metadata '(:category "smb" :mode "enumeration"))

(defun register-kali-command-tool-providers ()
  "Register argv-isolated fallback providers for the Kali-first tool catalog."
  (dolist (mapping (list-tool-mappings))
    (when (tool-mapping-executable mapping)
      (ensure-command-tool-provider
       (tool-mapping-capability mapping)
       (tool-mapping-provider mapping))))
  t)

(eval-when (:load-toplevel :execute)
  (register-kali-command-tool-providers))
