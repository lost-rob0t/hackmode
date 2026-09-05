{ pkgs, cl }:
let
  # Nixpkgs' generated Common Lisp package does not currently expose the
  # `sento` ASDF system to Hackmode's build reliably. Build the upstream
  # system explicitly so the actor runtime stays hermetic and discoverable.
  sentoSrc = builtins.fetchGit {
    url = "https://github.com/mdbergmann/cl-gserver.git";
    rev = "48f9b528becc8ed47be6c53fc288512f3fa732b9";
  };
in
pkgs.sbcl.buildASDFSystem {
  pname = "sento";
  version = "3.4.4";
  src = sentoSrc;
  systems = [ "sento" ];
  lispLibs = [
    cl.alexandria
    cl.log4cl
    cl."bordeaux-threads"
    cl."cl-speedy-queue"
    cl.str
    cl."binding-arrows"
    cl."timer-wheel"
    cl."local-time-duration"
    cl.atomics
  ];
  dontStrip = true;
}
