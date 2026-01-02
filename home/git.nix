{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    settings.user = {
      name = "67";
      email = "support@linux.com";
    };
  };
}