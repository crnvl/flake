# Webcam -> Jellyfin Live TV (shimmers side).
#
# Terminates the point-to-point wireguard link from corridors (see
# hosts/corridors/webcam.nix) and provides an M3U "tuner" file so Jellyfin can
# present the webcam as a Live TV channel.
#
# One-time Jellyfin setup (Dashboard -> Live TV -> Tuner Devices):
#   Add an "M3U Tuner" with file path /etc/jellyfin/webcam.m3u
# No guide (XMLTV) source is needed; the channel shows up under
# Live TV -> Channels with an empty guide.
{ config, ... }:

{
  age.secrets.wireguard-webcam-key.file = ../../../../hosts/shimmers/secrets/wireguard-webcam-key.age;

  networking = {
    firewall.allowedUDPPorts = [ 51821 ];

    wireguard.interfaces.wg-webcam = {
      ips = [ "10.100.0.1/24" ];
      listenPort = 51821;
      # Match corridors: the path between the two has a reduced MTU and the
      # default 1420 blackholes full-size packets (see hosts/corridors/webcam.nix).
      mtu = 1380;
      privateKeyFile = config.age.secrets.wireguard-webcam-key.path;

      peers = [
        {
          name = "corridors";
          # Auto-generated on corridors' first activation; read it there with
          #   sudo wg show wg-webcam public-key
          publicKey = "HRfdrfaf/uop4qdK/oiiX0WoA3eVEf0BS8L8+Z1LYCI=";
          allowedIPs = [ "10.100.0.2/32" ];
          # No endpoint: corridors is behind NAT and dials in with a
          # persistent keepalive.
        }
      ];
    };
  };

  environment.etc."jellyfin/webcam.m3u".text = ''
    #EXTM3U
    #EXTINF:-1 tvg-id="corridors-webcam" tvg-name="Corridors Webcam",Corridors Webcam
    rtsp://10.100.0.2:8554/webcam
  '';
}
