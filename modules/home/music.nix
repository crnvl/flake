{
  config,
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

  isoDir = "${config.home.homeDirectory}/music/ni-isos";

  ni-iso-rescue = pkgs.writeShellApplication {
    name = "ni-iso-rescue";
    text = ''
      src="${isoDir}"
      dst="$src/.rescue"

      mkdir -p "$dst"

      shopt -s nullglob
      for iso in "$src"/*.iso; do
        base="$(basename "$iso")"
        target="$dst/$base"

        if [ -e "$target" ] && [ "$iso" -ef "$target" ]; then
          continue
        fi

        rm -f "$target"

        if ln "$iso" "$target" 2>/dev/null; then
          echo "rescued: $base"
        else
          echo "could not hardlink: $base" >&2
        fi
      done
    '';
  };
in

{
  home = {
    packages = with pkgs; [
      carla
      lsp-plugins
      surge-xt
      ni-iso-rescue
    ];

    activation.musicDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      for dir in ${lib.concatStringsSep " " musicDirs}; do
        mkdir -p "$HOME/music/$dir"
      done
    '';
  };

  systemd.user = {
    paths.ni-iso-rescue = {
      Unit.Description = "Watch for Native Access ISO downloads";

      Path = {
        PathChanged = isoDir;
        PathExistsGlob = "${isoDir}/*.iso";
        Unit = "ni-iso-rescue.service";
      };

      Install.WantedBy = [ "default.target" ];
    };

    services.ni-iso-rescue = {
      Unit.Description = "Hardlink Native Access ISOs before they are deleted";

      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe ni-iso-rescue;
      };
    };
  };
}
