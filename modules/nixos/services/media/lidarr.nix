{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Lidarr keeps these in its database, so they are pushed through the API.
  #
  # Tags: Lidarr's default is to never write them, so imports kept whatever
  # the Soulseek uploader left in the file. Untagged ones showed up in
  # navidrome as [Unknown Artist], and the rest as near-duplicates ("Health"
  # next to "HEALTH"). "sync" tags every import from MusicBrainz and retags
  # whenever an album's metadata changes. Other tags (lyrics, replaygain)
  # are kept, only the fields Lidarr manages are overwritten.
  #
  # After that, any file whose tags still differ from what Lidarr would
  # write gets retagged: ones imported before the setting, or edited since.
  lidarrSettings = pkgs.writeShellApplication {
    name = "lidarr-settings";
    runtimeInputs = with pkgs; [
      curl
      jq
    ];
    text = ''
      url=http://localhost:8686/api/v1
      key="''${LIDARR__AUTH__APIKEY:?LIDARR__AUTH__APIKEY is not set}"

      log() { echo "lidarr-settings: $*" >&2; }

      # Lidarr may still be starting up, hence the generous retries.
      api() { # <method> <path> [json body]
        local args=(
          --fail-with-body --silent --show-error --max-time 120
          --retry 30 --retry-delay 2 --retry-connrefused
          --request "$1" --header "X-Api-Key: $key"
        )
        if [ "$#" -ge 3 ]; then
          args+=(--header "Content-Type: application/json" --data-binary "$3")
        fi
        curl "''${args[@]}" "$url/$2"
      }

      current="$(api GET config/metadataprovider)"
      wanted="$(jq -c '.writeAudioTags = "sync" | .scrubAudioTags = false' <<< "$current")"
      if [ "$(jq -S . <<< "$current")" != "$(jq -S . <<< "$wanted")" ]; then
        api PUT "config/metadataprovider/$(jq -r .id <<< "$wanted")" "$wanted" > /dev/null
        log "audio tags are now written on import and kept in sync with MusicBrainz"
      fi

      for artist in $(api GET artist | jq -r '.[].id'); do
        files="$(api GET "retag?artistId=$artist" | jq -c 'map(.trackFileId) | unique')"
        [ "$(jq length <<< "$files")" -gt 0 ] || continue
        api POST command "$(jq -nc --argjson a "$artist" --argjson f "$files" \
          '{ name: "RetagFiles", artistId: $a, files: $f }')" > /dev/null
        log "artist $artist: retagging $(jq length <<< "$files") files"
      done
    '';
  };
in
{
  # Contains LIDARR__AUTH__APIKEY=... so the API key is pinned declaratively
  # and can be shared with soularr (soularr-env) without copying it out of
  # the UI.
  age.secrets.lidarr-env.file = ../../../../hosts/shimmers/secrets/lidarr-env.age;

  services.lidarr = {
    enable = true;
    openFirewall = false;
    environmentFiles = [ config.age.secrets.lidarr-env.path ];
  };

  systemd.services.lidarr = {
    vpnConfinement = {
      enable = true;
      vpnNamespace = "wg";
    };
    unitConfig.RequiresMountsFor = [ "/mnt/chroma" ];
  };

  # On every Lidarr start, and daily to undo changes made in the web UI.
  systemd.services.lidarr-settings = {
    description = "apply the Lidarr settings kept in nix and retag drifted files";
    after = [ "lidarr.service" ];
    wantedBy = [ "lidarr.service" ];
    startAt = "daily";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe lidarrSettings;
      EnvironmentFile = config.age.secrets.lidarr-env.path;
      DynamicUser = true;
    };
  };

  my.vpn.confinedServices = [ "lidarr-settings" ];

  # media: /mnt/chroma library, sabnzbd/qbittorrent downloads, and the slskd
  # downloads dir (setgid media, see slskd.nix) so imports can move files out.
  # sabnzbd: its job dirs are created sabnzbd:sabnzbd, so moving finished
  # downloads out needs that group (same as sonarr and radarr).
  users.users.lidarr.extraGroups = [
    "media"
    "sabnzbd"
  ];

  my.vpn.portMappings = [
    {
      from = 8686;
      to = 8686;
    }
  ];
}
