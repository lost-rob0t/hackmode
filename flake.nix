{
  description = "Hackmode is a red teaming toolkit/exploit framework for common lisp";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
  };

  outputs = { self, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in
    {
      devShell.x86_64-linux =
        pkgs.mkShell {
          buildInputs = with pkgs; [
            pkg-config
            sbcl
            sbclPackages.mcclim
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
           export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath([pkgs.openssl])}:${pkgs.lib.makeLibraryPath([pkgs.libedit])}:${pkgs.lib.makeLibraryPath([pkgs.libev])}:${pkgs.lib.makeLibraryPath([pkgs.lmdb])}
          '';
        };
    };
}
