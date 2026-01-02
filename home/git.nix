{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "67";
    userEmail = "support@linux.com";
  };
}