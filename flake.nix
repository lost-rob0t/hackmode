{
  description = "project desc";

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
            sbclPackages.qlot
            sbclPackages.mcclim
            glib
            openssl
              pkgs.clang
            pkgs.libedit
            pkgs.sbcl
            pkgs.ccl


            # Hacking tools used
            subfinder
          ];

        shellHook = ''
           export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath([pkgs.openssl])}:${pkgs.lib.makeLibraryPath([pkgs.libedit])}:${pkgs.lib.makeLibraryPath([pkgs.libev])}:${pkgs.lib.makeLibraryPath([pkgs.lmdb])}
          '';
        };
    };
}
