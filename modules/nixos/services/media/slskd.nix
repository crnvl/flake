{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Contains:
  #   SLSKD_SLSK_USERNAME=...  Soulseek network account (auto-registered on
  #   SLSKD_SLSK_PASSWORD=...  first login if the name is free)
  #   SLSKD_USERNAME=...       web UI login
  #   SLSKD_PASSWORD=...
  #   SLSKD_API_KEY=...        primary (admin) API key, shared with Lidarr's
  #                            Tubifarry providers (see lidarr.nix)
  age.secrets.slskd-env.file = ../../../../hosts/shimmers/secrets/slskd-env.age;

  services.slskd = {
    enable = true;
    openFirewall = false;
    environmentFile = config.age.secrets.slskd-env.path;

    settings = {
      directories = {
        incomplete = "/var/lib/slskd/incomplete";
        downloads = "/var/lib/slskd/downloads";
      };

      # Share the library back; many Soulseek users refuse to serve
      # non-sharers. Read-only (the module adds it to ReadOnlyPaths). With no
      # port forwarding (see below) only peers that accept connections can
      # reach us, so a bigger share is the main lever left: aurral's
      # playlist folder (media/music/playlists) is shared too.
      shares.directories = [ "/mnt/chroma/media/music" ];
      # Rescan hourly (minutes; 60 is the minimum). By default slskd only
      # scans at startup, so imports and Lidarr's renames left it advertising
      # files that had moved, and kept the share looking smaller than it is.
      shares.cache.retention = 60;

      # Mullvad has no port forwarding, so nothing reaches this from outside;
      # we can only connect out to peers that accept inbound connections.
      soulseek.listen_port = 50300;
    };
  };

  # Pinned when soularr's container ran as the same uid/gid (podman can't
  # resolve host user names); kept so existing files keep their owner. 360
  # is outside both the NixOS static id table and the dynamic system-user
  # range.
  users.users.slskd.uid = 360;
  users.groups.slskd.gid = 360;

  systemd.services.slskd = {
    vpnConfinement = {
      enable = true;
      vpnNamespace = "wg";
    };

    serviceConfig = {
      # Group-writable so lidarr (via the setgid media dirs below) can move
      # completed downloads out on import.
      UMask = "0002";
      # The upstream module sets PrivateUsers=true; inside a private user
      # namespace the media group is unmapped and joining the wg netns
      # (NetworkNamespacePath) can fail for lack of privileges.
      PrivateUsers = lib.mkForce false;
    };

    unitConfig.RequiresMountsFor = [ "/mnt/chroma" ];
  };

  # slskd reconnects by itself after a clean disconnect, but its server
  # connection can also hang in "Disconnecting" and then never reconnect (on
  # 2026-11-26 it sat like that for 17 hours). Every search fails meanwhile,
  # so aurral's and Lidarr's queues stall. Restarts slskd once it has not
  # been logged in for 5 minutes straight. Runs on the host and reaches the
  # API through the namespace's port mapping.
  systemd.services.slskd-login-watchdog = {
    description = "restart slskd when it stays logged out of Soulseek";
    after = [ "slskd.service" ];
    startAt = "*:0/5";
    path = with pkgs; [
      curl
      jq
    ];
    script = ''
      systemctl is-active --quiet slskd.service || exit 0
      for _ in $(seq 10); do
        if curl --silent --max-time 10 --header "X-API-Key: $SLSKD_API_KEY" \
          http://${config.vpnNamespaces.wg.namespaceAddress}:5030/api/v0/server \
          | jq -e .isLoggedIn > /dev/null; then
          exit 0
        fi
        sleep 30
      done
      systemctl is-active --quiet slskd.service || exit 0
      echo "slskd has not been logged in to Soulseek for 5 minutes, restarting it"
      systemctl restart slskd.service
    '';
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.age.secrets.slskd-env.path;
    };
  };

  # The state dir itself must be created with the right owner up front:
  # otherwise tmpfiles makes it root-owned and systemd's StateDirectory=
  # handling then recursively chowns everything to slskd:slskd, clobbering
  # the media group below.
  # Downloads untouched for two weeks are removed: Lidarr and aurral move
  # what they want out within minutes, the rest is failed or partial albums.
  systemd.tmpfiles.rules = [
    "d /var/lib/slskd 0755 slskd slskd -"
    "d /var/lib/slskd/incomplete 2775 slskd media -"
    "d /var/lib/slskd/downloads 2775 slskd media 14d"
  ];

  my.vpn.ports = [ 5030 ];
}
