{ ... }:

let
  keys = import ../../keys.nix;
  sshKeys = builtins.attrValues keys.users;
in
{
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  security.sudo.wheelNeedsPassword = false;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  users.users.aleph.openssh.authorizedKeys.keys = sshKeys;
  users.users.root.openssh.authorizedKeys.keys = sshKeys;
}
