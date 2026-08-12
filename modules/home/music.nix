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

  pluginPath =
    subdir:
    lib.concatStringsSep ":" [
      "$HOME/.${subdir}"
      "${config.home.profileDirectory}/lib/${subdir}"
      "/run/current-system/sw/lib/${subdir}"
    ];
in

{
  home = {
    packages = with pkgs; [
      carla
      lsp-plugins
      surge-xt
    ];

    sessionVariables = {
      LV2_PATH = pluginPath "lv2";
      VST3_PATH = pluginPath "vst3";
      CLAP_PATH = pluginPath "clap";
      VST_PATH = pluginPath "vst";
      LADSPA_PATH = pluginPath "ladspa";
    };

    activation.musicDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      for dir in ${lib.concatStringsSep " " musicDirs}; do
        mkdir -p "$HOME/music/$dir"
      done
    '';
  };
}
