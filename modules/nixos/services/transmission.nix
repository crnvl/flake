{ config, pkgs, ... }:

let
  mullvadAddress = "10.71.119.114/32";
  mullvadEndpoint = "135.136.19.130:51820";
  mullvadPeerKey = "WPaUZB1eO0W/F4GMDk8uVgqQfS5q4P9F53/pbLmlDjs=";
  mullvadDns = "10.64.0.1";
in
{
  age.secrets.mullvad-wg-private-key = {
    file = ../../../hosts/shimmers/secrets/mullvad-wg-private-key.age;
  };

  services.transmission = {
    enable = true;
    settings = {
      rpc-bind-address = "10.200.0.2";
      rpc-port = 9091;
      rpc-whitelist-enabled = false;
      download-dir = "/var/lib/transmission/downloads";
      incomplete-dir = "/var/lib/transmission/incomplete";
      incomplete-dir-enabled = true;
    };
  };

  boot.kernelModules = [ "wireguard" ];

  systemd = {
    services = {
      transmission = {
        serviceConfig.NetworkNamespacePath = "/run/netns/mullvad";
        after = [ "mullvad-netns.service" ];
        requires = [ "mullvad-netns.service" ];
      };

      mullvad-netns = {
        description = "Mullvad WireGuard VPN namespace";
        wantedBy = [ "multi-user.target" ];
        before = [ "transmission.service" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStop = "${pkgs.iproute2}/bin/ip netns del mullvad";
        };

        path = [
          pkgs.iproute2
          pkgs.wireguard-tools
        ];

        script = ''
          # Create namespace
          ip netns add mullvad || true
          ip -n mullvad link set lo up

          # Create WireGuard interface in namespace
          ip link add wg0 type wireguard
          ip link set wg0 netns mullvad

          # Configure WireGuard (inside namespace since wg0 is there now)
          ip netns exec mullvad wg set wg0 \
            private-key ${config.age.secrets.mullvad-wg-private-key.path} \
            peer ${mullvadPeerKey} \
            endpoint ${mullvadEndpoint} \
            allowed-ips 0.0.0.0/0,::0/0

          ip -n mullvad addr add ${mullvadAddress} dev wg0
          ip -n mullvad link set wg0 up
          ip -n mullvad route add default dev wg0

          # DNS inside namespace
          mkdir -p /etc/netns/mullvad
          echo "nameserver ${mullvadDns}" > /etc/netns/mullvad/resolv.conf

          # Port forward: host:9091 -> namespace:9091 (for Sonarr/Radarr)
          ip link add veth-host type veth peer name veth-mullvad
          ip link set veth-mullvad netns mullvad
          ip addr add 10.200.0.1/24 dev veth-host
          ip -n mullvad addr add 10.200.0.2/24 dev veth-mullvad
          ip link set veth-host up
          ip -n mullvad link set veth-mullvad up
        '';
      };
    };

    tmpfiles.rules = [
      "d /var/lib/transmission/downloads 0755 transmission transmission -"
      "d /var/lib/transmission/incomplete 0755 transmission transmission -"
    ];
  };
}
