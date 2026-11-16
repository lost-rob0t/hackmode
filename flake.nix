{
  description = "Hackmode is a red teaming toolkit/exploit framework for common lisp";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/bfc1b8a4574108ceef22f02bafcf6611380c100d";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          runtimeLibs = with pkgs; [
            openssl
            libedit
            libev
            lmdb
          ];
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              pkg-config
              sbcl
              sbclPackages.mcclim
              swi-prolog
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
              export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath runtimeLibs}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            '';
          };
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
