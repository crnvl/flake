{ ... }:

let
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIXBwAlJ0BxHk01MZ5QnVHbmS5tgO+Rubg0MyJsIk5dp" # corridors
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH++Jm6a+gQf5yEdTzT5ozuIQdkYb2w98UxsX2I1YJlg" # chambers
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICbVo7Bj9I6oZc8cM4IPDNhF6MSns8X8S8HrVhql/PxV" # macbook
  ];
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
