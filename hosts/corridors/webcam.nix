# Webcam -> Jellyfin Live TV (corridors side).
#
# go2rtc exposes the USB webcam as an on-demand HLS stream; shimmers' Jellyfin
# tunes into it over a point-to-point wireguard link (see
# modules/nixos/services/media/webcam-livetv.nix for the other end). ffmpeg
# only runs (and upload bandwidth is only used) while someone is actually
# watching the channel.
#
# The wireguard private key is generated on first activation
# (generatePrivateKeyFile), so no agenix secret is needed on this host. After
# the first rebuild, read the public key with
#   sudo wg show wg-webcam public-key
# and paste it into the corridors peer in webcam-livetv.nix.
{ ... }:

{
  services.go2rtc = {
    enable = true;
    settings = {
      api.listen = ":1984";
      streams.webcam =
        "ffmpeg:device?video=/dev/v4l/by-id/usb-Rapoo_Camera_Rapoo_Camera_SN0001-video-index0"
        + "&input_format=mjpeg&video_size=1920x1080&framerate=30"
        + "#video=h264";
    };
  };

  networking = {
    # go2rtc listens on all interfaces, but only the wireguard link (and
    # localhost, which bypasses the filter) may actually reach it.
    # 1984 = HTTP API, 8554 = RTSP (what Jellyfin consumes; go2rtc's
    # session-based HLS hangs ffprobe, RTSP is reliable and lower-latency).
    firewall.interfaces.wg-webcam.allowedTCPPorts = [
      1984
      8554
    ];

    wireguard.interfaces.wg-webcam = {
      ips = [ "10.100.0.2/24" ];
      # The path to shimmers has a reduced MTU (~1452 outer, measured
      # 2026-10-02); wireguard's default 1420 gets full-size packets silently
      # blackholed. 1380 leaves headroom.
      mtu = 1380;
      privateKeyFile = "/var/lib/wireguard/webcam.key";
      generatePrivateKeyFile = true;

      peers = [
        {
          name = "shimmers";
          publicKey = "E6HZc3W1JDjCavz8BiOU1BPg6BGS7P//Omc85bbHs2Q=";
          allowedIPs = [ "10.100.0.1/32" ];
          endpoint = "shimme.rs:51821";
          # We're behind NAT and shimmers can't reach in; keep the hole open.
          persistentKeepalive = 25;
          # Re-resolve the endpoint periodically so a failed DNS lookup at
          # boot (or a changed A record) heals itself.
          dynamicEndpointRefreshSeconds = 60;
        }
      ];
    };
  };
}
