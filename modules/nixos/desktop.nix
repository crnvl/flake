{ pkgs, ... }:

{
  fonts = {
    fontDir.enable = true;
    fontconfig.enable = true;
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
    ];
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
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

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
    ];
  };

  security.pam.services.greetd.enableGnomeKeyring = true;

  users.users.aleph = {
    extraGroups = [
      "video"
      "audio"
    ];
  };

  environment.systemPackages = with pkgs; [
    xwayland-satellite
    waybar
    glib
    libpulseaudio
    libGL
    libx11
    libxext
    libxrender
    libxtst
    libxi
    libxrandr
    protontricks
    bluez
  ];
}
