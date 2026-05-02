{ pkgs, ... }:

{
  fonts = {
    fontDir.enable = true;
    fontconfig.enable = true;
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
    ];
  };

  programs = {
    niri = {
      enable = true;
      package = pkgs.niri;
    };

    ssh.startAgent = true;
  };

  services = {
    mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
    };

    gnome = {
      gcr-ssh-agent.enable = false;
      gnome-keyring.enable = true;
    };
  };

  security.pam.services.greetd.enableGnomeKeyring = true;

  users.users.aleph = {
    extraGroups = [
      "video"
      "audio"
    ];
  };

  environment = {
    variables.SSH_AUTH_SOCK = "/run/user/1000/ssh-agent";

    systemPackages = with pkgs; [
      xwayland-satellite
      waybar
      hyfetch
      glib
      libpulseaudio
      libGL
      libx11
      libxext
      libxrender
      libxtst
      libxi
      libxrandr
    ];
  };
}
