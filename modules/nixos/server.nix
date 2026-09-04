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

  boot.kernel.sysctl."net.ipv4.tcp_mtu_probing" = 1;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];

    extraCommands = ''
      iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1400
    '';
    extraStopCommands = ''
      iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1400 || true
    '';
  };

  users.users.aleph.openssh.authorizedKeys.keys = sshKeys;
  users.users.root.openssh.authorizedKeys.keys = sshKeys;
}
