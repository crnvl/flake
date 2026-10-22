{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Posts slskd events to Discord. slskd's own webhooks send its raw event
  # JSON, which Discord rejects, so this runs as a slskd script instead and
  # builds the message with slskd-discord.jq. slskd starts it directly (no
  # shell) with the event in $SLSKD_SCRIPT_DATA; that data comes from the
  # Soulseek network and is only ever handled by jq. Runs inside slskd's
  # unit, so the request leaves through the VPN like everything else.
  discordNotify = pkgs.writeShellApplication {
    name = "slskd-discord";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
    ];
    text = ''
      url="$(tr -d '[:space:]' < ${config.age.secrets.slskd-discord-webhook.path})"
      jq -nc -f ${./slskd-discord.jq} \
        | curl --fail --silent --show-error --max-time 20 \
            --header 'Content-Type: application/json' \
            --data @- "$url" > /dev/null
    '';
  };
in
{
  # Contains:
  #   SLSKD_SLSK_USERNAME=...  Soulseek network account (auto-registered on
  #   SLSKD_SLSK_PASSWORD=...  first login if the name is free)
  #   SLSKD_USERNAME=...       web UI login
  #   SLSKD_PASSWORD=...
  #   SLSKD_API_KEY=...        primary (admin) API key, shared with soularr
  age.secrets.slskd-env.file = ../../../../hosts/shimmers/secrets/slskd-env.age;

  # Discord webhook URL for the Soulseek channel.
  age.secrets.slskd-discord-webhook = {
    file = ../../../../hosts/shimmers/secrets/slskd-discord-webhook.age;
    owner = "slskd";
    group = "slskd";
  };

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
      # non-sharers. Read-only (the module adds it to ReadOnlyPaths).
      shares.directories = [ "/mnt/chroma/media/music" ];

      # Mullvad has no port forwarding, so nothing reaches this from outside;
      # we can only connect out to peers that accept inbound connections.
      soulseek.listen_port = 50300;

      # Finished album folders and private messages go to Discord. Per-file
      # completions would be one message per track, and uploads from the
      # share would flood the channel.
      integrations.scripts.discord = {
        on = [
          "DownloadDirectoryComplete"
          "PrivateMessageReceived"
        ];
        run.executable = lib.getExe discordNotify;
      };
    };
  };

  # Pinned so soularr's container can run as the same uid/gid (podman can't
  # resolve host user names). 360 is outside both the NixOS static id table
  # and the dynamic system-user range.
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

  # The state dir itself must be created with the right owner up front:
  # otherwise tmpfiles makes it root-owned and systemd's StateDirectory=
  # handling then recursively chowns everything to slskd:slskd, clobbering
  # the media group below.
  systemd.tmpfiles.rules = [
    "d /var/lib/slskd 0755 slskd slskd -"
    "d /var/lib/slskd/incomplete 2775 slskd media -"
    "d /var/lib/slskd/downloads 2775 slskd media -"
  ];

  my.vpn.ports = [ 5030 ];
}
