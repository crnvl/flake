{ pkgs, ... }:

{
  fonts.fontDir.enable = true;
  fonts.fontconfig.enable = true;
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  programs.niri.enable = true;

  users.users.aleph = {
    extraGroups = [
      "video"
      "audio"
    ];
  };

  environment.systemPackages = with pkgs; [
    xwayland-satellite
    waybar
    hyfetch
    glib
    libpulseaudio
    libGL
    libx11
    libxext
    libxrender
    libxstst
    libxi
    libxrandr
  ];
}
