{
  description = "Hackmode actor-oriented reconnaissance and investigation environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      eachSystem = f: nixpkgs.lib.genAttrs systems (system: f system);

      mkSystem = system:
        let
          pkgs = import nixpkgs { inherit system; };
          cl = pkgs.sbcl.pkgs;

          runtimeLibs = with pkgs; [
            lmdb
            openssl
            libffi
            libev
            libedit
            file
          ];

          runtimeTools = with pkgs; [
            curl
            nmap
            subfinder
            amass
            dnsrecon
            fierce
            asn
            whatweb
            nuclei
            zap
            gospider
            swi-prolog
          ];

          # Hackmode historically consumed Lish through Quicklisp. Keep the
          # exact Yew/Lish snapshot explicit so the expert shell is buildable
          # without relying on a mutable local Quicklisp tree.
          yewSrc = builtins.fetchGit {
            url = "https://github.com/lost-rob0t/yew-for-hackmode.git";
            rev = "33e87d3f8e8972da1b8162ba67ffd41bee447cfb";
          };

          lish = pkgs.sbcl.buildASDFSystem {
            pname = "hackmode-lish";
            version = "0.1.0-hackmode";
            src = yewSrc;
            systems = [
              "dlib"
              "opsys"
              "dlib-misc"
              "stretchy"
              "char-util"
              "glob"
              "table"
              "table-print"
              "reader-ext"
              "dlib-interactive"
              "completion"
              "keymap"
              "terminal"
              "terminal-ansi"
              "rl"
              "fatchar"
              "fatchar-io"
              "magic"
              "theme"
              "theme-default"
              "style"
              "collections"
              "ostring"
              "ochar"
              "grout"
              "utf8b-stream"
              "dtime"
              "locale"
              "lish"
            ];
            nativeLibs = [ pkgs.file ];
            lispLibs = [
              cl.alexandria
              cl.babel
              cl."bordeaux-threads"
              cl.cffi
              cl.chipz
              cl."cl-ppcre"
              cl."closer-mop"
              cl."trivial-gray-streams"
            ];
            dontStrip = true;
          };

          tek9Src = builtins.fetchGit {
            url = "https://github.com/lost-rob0t/tek9.git";
            rev = "1cb978084da8b4f1d184b3ef2a1d30057f525608";
          };

          lmdbLisp = cl.lmdb.overrideLispAttrs (old: {
            nativeLibs = (old.nativeLibs or [ ]) ++ [ pkgs.lmdb.out ];
          });

          tek9 = pkgs.sbcl.buildASDFSystem {
            pname = "tek9";
            version = "0.2.0";
            src = tek9Src;
            systems = [ "tek9" ];
            nativeLibs = [ pkgs.lmdb.out ];
            lispLibs = [
              cl.alexandria
              cl."bordeaux-threads"
              cl.serapeum
              cl.jsown
              lmdbLisp
              cl."cl-conspack"
            ];
          };

          starClSrc = builtins.fetchGit {
            url = "https://github.com/lost-rob0t/star-cl.git";
            rev = "b8dfbe2f9f56065ace8c3313b92ca748a115cdfa";
          };

          cmsUlid = pkgs.sbcl.buildASDFSystem {
            pname = "cms-ulid";
            version = "latest";
            src = pkgs.fetchgit {
              url = "https://gitlab.com/colinstrickland/cms-ulid.git";
              rev = "fff84302dee5db42fb90aafd834af3ffbfd6c2bb";
              hash = "sha256-B5rekME60bWHk47kDepQpOr9drjgXjZBiRpA+Ob1CuU=";
            };
            lispLibs = [
              cl."local-time"
              cl.ironclad
              cl."bit-smasher"
              cl.serapeum
            ];
            dontStrip = true;
          };

          starintel = pkgs.sbcl.buildASDFSystem {
            pname = "starintel";
            version = "0.9.0";
            src = starClSrc;
            systems = [ "starintel" ];
            asdFilesToKeep = [
              "src/starintel.asd"
              "starintel-v090.asd"
              "starintel-test.asd"
            ];
            lispLibs = [
              cl.jsown
              cl.jzon
              cl."cl-ppcre"
              cl.ironclad
              cl."local-time"
              cmsUlid
              cl.str
              cl."closer-mop"
            ];
            dontStrip = true;
          };

          # Nixpkgs currently exposes an nfiles Lisp derivation that does not
          # make the `nfiles` ASDF system discoverable from buildASDFSystem.
          # Pin and build the exact upstream system so Hackmode's dependency is
          # hermetic instead of falling back to a mutable Quicklisp tree.
          nfilesSrc = builtins.fetchGit {
            url = "https://github.com/atlas-engineer/nfiles.git";
            rev = "b44b06caf20cececeaee2153a747902c508a9c48";
          };

          nfiles = pkgs.sbcl.buildASDFSystem {
            pname = "nfiles";
            version = "1.1.4";
            src = nfilesSrc;
            systems = [ "nfiles" ];
            lispLibs = [
              cl.alexandria
              cl.nclasses
              cl.quri
              cl.serapeum
              cl."trivial-garbage"
              cl."trivial-package-local-nicknames"
              cl."trivial-types"
            ];
            dontStrip = true;
          };

          hackmodeDatabase = pkgs.sbcl.buildASDFSystem {
            pname = "hackmode-database";
            version = "0.1.0";
            src = ./source/hackmode-database;
            systems = [ "hackmode-database" ];
            lispLibs = [ tek9 ];
            nativeLibs = [ pkgs.lmdb.out ];
            dontStrip = true;
          };

          hackmodeCore = pkgs.sbcl.buildASDFSystem {
            pname = "hackmode";
            version = "0.3.0";
            src = ./source/hackmode-core;
            systems = [ "hackmode" ];
            nativeLibs = runtimeLibs;
            lispLibs = [
              cl.serapeum
              cl."local-time"
              nfiles
              cl.nhooks
              cl."bordeaux-threads"
              tek9
              hackmodeDatabase
              starintel
              cl.jsown
              cl."cl-ppcre"
              cl.dexador
              cl.sento
              cl.shellpool
            ];
            dontStrip = true;
          };

          providerDns = pkgs.sbcl.buildASDFSystem {
            pname = "hackmode-provider-dns";
            version = "0.1.0";
            src = ./source/hackmode-providers/dns;
            systems = [ "hackmode-provider-dns" ];
            lispLibs = [ hackmodeCore cl.jsown ];
            nativeLibs = runtimeLibs;
            dontStrip = true;
          };

          providerRecon = pkgs.sbcl.buildASDFSystem {
            pname = "hackmode-provider-recon";
            version = "0.1.0";
            src = ./source/hackmode-providers/recon;
            systems = [ "hackmode-provider-recon" ];
            lispLibs = [ hackmodeCore cl.jsown cl.dexador ];
            nativeLibs = runtimeLibs;
            dontStrip = true;
          };

          hackmodeUser = pkgs.sbcl.buildASDFSystem {
            pname = "hackmode-user";
            version = "0.2.0";
            src = self;
            systems = [ "hackmode-user" ];
            asdFilesToKeep = [ "hackmode-user.asd" ];
            lispLibs = [
              hackmodeCore
              providerDns
              providerRecon
              lish
              cl.shellpool
            ];
            nativeLibs = runtimeLibs;
            dontStrip = true;
          };

          sbclRuntime = pkgs.sbcl.withPackages (_: [ hackmodeUser ]);

          launcher = pkgs.writeText "hackmode-launcher.lisp" ''
            (let ((asdf-path (sb-ext:posix-getenv "ASDF")))
              (when asdf-path
                (load asdf-path)))
            (asdf:load-system :hackmode-user)
            (hackmode-user:main)
          '';

          hm = pkgs.writeShellApplication {
            name = "hm";
            runtimeInputs = runtimeTools;
            text = ''
              export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath runtimeLibs}:''${LD_LIBRARY_PATH:-}"
              exec ${sbclRuntime}/bin/sbcl --noinform --script ${launcher} "$@"
            '';
          };

          expert = pkgs.writeShellApplication {
            name = "hm-expert";
            runtimeInputs = [ hm ];
            text = ''
              exec ${hm}/bin/hm expert "$@"
            '';
          };

          hackmode = pkgs.symlinkJoin {
            name = "hackmode-0.2.0";
            paths = [ hm expert ];
          };
        in
        {
          inherit
            pkgs
            runtimeLibs
            runtimeTools
            lish
            hackmode
            hm
            expert
            ;
        };
    in
    {
      # Public package API. Build internals stay private in mkSystem so
      # `nix flake show` presents a small stable interface to users.
      packages = eachSystem (system:
        let
          built = mkSystem system;
        in
        {
          default = built.hackmode;
          inherit (built) hm expert;
        });

      apps = eachSystem (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.hm}/bin/hm";
        };
        hm = {
          type = "app";
          program = "${self.packages.${system}.hm}/bin/hm";
        };
        expert = {
          type = "app";
          program = "${self.packages.${system}.expert}/bin/hm-expert";
        };
      });

      checks = eachSystem (system:
        let
          built = mkSystem system;
          pkgs = built.pkgs;
          lishRuntime = pkgs.sbcl.withPackages (_: [ built.lish ]);
        in
        {
          public-output-contract =
            let
              packageNames = builtins.attrNames self.packages.${system};
              appNames = builtins.attrNames self.apps.${system};
            in
            assert packageNames == [ "default" "expert" "hm" ];
            assert appNames == [ "default" "expert" "hm" ];
            pkgs.runCommand "hackmode-public-output-contract" { } ''
              test -x ${self.packages.${system}.default}/bin/hm
              test -x ${self.packages.${system}.default}/bin/hm-expert
              test -x ${self.packages.${system}.hm}/bin/hm
              test -x ${self.packages.${system}.expert}/bin/hm-expert
              touch "$out"
            '';

          lish-compiles = pkgs.runCommand "hackmode-lish-compiles" {
            nativeBuildInputs = [ lishRuntime ];
          } ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            sbcl --noinform --non-interactive --no-userinit --no-sysinit \
              --eval '(require :asdf)' \
              --eval '(asdf:load-system :lish)' \
              --eval '(assert (find-package :lish))'
            touch "$out"
          '';

          cli-help = pkgs.runCommand "hackmode-cli-help" {
            nativeBuildInputs = [ self.packages.${system}.hm ];
          } ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            hm --help | grep -q 'hm scan TARGET'
            hm --help | grep -q 'hm inventory import FILE'
            touch "$out"
          '';

          expert-entrypoint = pkgs.runCommand "hackmode-expert-entrypoint" {
            nativeBuildInputs = [ self.packages.${system}.expert ];
          } ''
            command -v hm-expert >/dev/null
            test -x "$(command -v hm-expert)"
            touch "$out"
          '';

          inventory-import = pkgs.runCommand "hackmode-inventory-import" {
            nativeBuildInputs = [ self.packages.${system}.hm ];
          } ''
            export HOME="$TMPDIR/home"
            export XDG_CONFIG_HOME="$HOME/.config"
            export XDG_DATA_HOME="$HOME/.local/share"
            mkdir -p "$HOME" "$TMPDIR/work"
            cd "$TMPDIR/work"
            printf '%s\n' 'example.internal' '192.0.2.10' > inventory.txt
            hm inventory import inventory.txt
            test -f .hackmode/data.mdb
            touch "$out"
          '';
        });

      devShells = eachSystem (system:
        let
          built = mkSystem system;
          pkgs = built.pkgs;
        in
        {
          default = pkgs.mkShell {
            packages = [
              built.hackmode
              built.lish
              pkgs.pkg-config
              pkgs.sbcl
              pkgs.glib
              pkgs.openssl
              pkgs.lmdb
              pkgs.subfinder
              pkgs.amass
              pkgs.dnsrecon
              pkgs.fierce
              pkgs.asn
              pkgs.whatweb
              pkgs.nmap
              pkgs.nuclei
              pkgs.zap
              pkgs.gospider
              pkgs.swi-prolog
            ];
            shellHook = ''
              export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath built.runtimeLibs}:''${LD_LIBRARY_PATH:-}
              echo "Hackmode development environment"
              echo "Run: hm --help"
              echo "Expert: hm-expert"
              echo "Check: nix flake check"
            '';
          };
        });
    };
}
