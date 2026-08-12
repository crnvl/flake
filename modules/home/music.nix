{
  lib,
  pkgs,
  ...
}:

let
  musicDirs = [
    "projects"
    "samples"
    "ni-content"
    "ni-isos"
  ];
in

{
  home = {
    packages = with pkgs; [
      carla
      lsp-plugins
      surge-xt
    ];

    activation.musicDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      for dir in ${lib.concatStringsSep " " musicDirs}; do
        mkdir -p "$HOME/music/$dir"
      done
    '';
  };
}
