{
  description = "Hackmode is a red teaming toolkit/exploit framework for common lisp";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    star-lang = {
      url = "github:lost-rob0t/star-lang/09f3b6dab15a9bcb9b5dd7866735d65301571211";
      flake = false;
    };
    tek9 = {
      url = "github:lost-rob0t/tek9/e6d1cb86a2e268a894eae3acae9617238b2adcff";
      flake = false;
    };
    star-cl = {
      url = "github:lost-rob0t/star-cl/b8dfbe2f9f56065ace8c3313b92ca748a115cdfa";
      flake = false;
    };
    cl-gserver = {
      url = "github:mdbergmann/cl-gserver/6a510c5b58469e72e6363bd3a6059d80b9a5c320";
      flake = false;
    };
    cms-ulid = {
      url = "gitlab:colinstrickland/cms-ulid/fff84302dee5db42fb90aafd834af3ffbfd6c2bb";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, star-lang, tek9, star-cl, cl-gserver, cms-ulid }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Ordered so the repository under test and the pinned dependencies win
      # over anything the nix store registry prepends.
      sourceRegistry = pkgs.lib.concatStringsSep ":" [
        "${self}//"
        "${star-lang}//"
        "${tek9}/src//"
        "${star-cl}/src//"
        "${cl-gserver}//"
        "${cms-ulid}//"
      ];

      sbcl = pkgs.sbcl.withPackages (ps: with ps; [
        serapeum
        local-time
        nfiles
        nhooks
        bordeaux-threads
        jsown
        cl-ppcre
        ironclad
        dexador
        str
        yason
        usocket
        cffi
        babel
        swank
      ]);

      hackmodeActorsTest = pkgs.stdenvNoCC.mkDerivation {
        pname = "hackmode-actors-tests";
        version = "0.1.0";
        src = pkgs.lib.cleanSource ./.;

        strictDeps = true;
        nativeBuildInputs = [ sbcl pkgs.swi-prolog ];

        dontConfigure = true;
        dontBuild = true;

        checkPhase = ''
          runHook preCheck
          export HOME="$TMPDIR/home"
          mkdir -p "$HOME"
          export CL_SOURCE_REGISTRY="${sourceRegistry}:$CL_SOURCE_REGISTRY"
          sbcl --non-interactive \
            --eval '(require :asdf)' \
            --eval '(asdf:load-asd (truename "source/hackmode-actors/hackmode-actors.asd"))' \
            --eval '(asdf:load-asd (truename "source/hackmode-actors/tests/hackmode-actors-tests.asd"))' \
            --eval '(asdf:test-system :hackmode-actors)'
          runHook postCheck
        '';
        doCheck = true;
      };
    in
    {
      devShell.${system} =
        pkgs.mkShell {
          buildInputs = with pkgs; [
            pkg-config
            sbcl
            sbclPackages.mcclim
            swiProlog
            glib
            openssl
            # Hacking tools used
            subfinder
            amass
            dnsrecon
            fierce
            asn
            whatweb
            nmap
            nuclei
            zap
            gospider
          ];

          shellHook = ''
            export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath ([ pkgs.openssl pkgs.libedit pkgs.libev pkgs.lmdb ])}:''${LD_LIBRARY_PATH:-}
            export CL_SOURCE_REGISTRY="${sourceRegistry}:''${CL_SOURCE_REGISTRY:-}"
          '';
        };

      checks.${system} = { inherit hackmodeActorsTest; };
    };
}
