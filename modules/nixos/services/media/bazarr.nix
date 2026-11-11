{
  config,
  lib,
  pkgs,
  mkProxyHost,
  ...
}:

let
  domain = "bazarr.shimme.rs";
  port = 6767;
  secret = name: { _secret = config.age.secrets.${name}.path; };

  # Bazarr keeps its languages and language profiles in its database, so
  # they are pushed through the API, like lidarr-settings does: German and
  # English on everything. The profile is also the default for new series
  # and movies (below); this gives it to the ones Bazarr synced before the
  # profile existed, and to anything whose profile was unset in the UI.
  bazarrSettings = pkgs.writeShellApplication {
    name = "bazarr-settings";
    runtimeInputs = with pkgs; [
      curl
      jq
    ];
    text = ''
      url=http://localhost:${toString port}/api
      key="$(< "$CREDENTIALS_DIRECTORY/apikey")"

      api() { # <method> <path> [curl args...]
        local method=$1 path=$2
        shift 2
        curl --fail-with-body --silent --show-error --max-time 120 \
          --retry 30 --retry-delay 2 --retry-connrefused \
          --request "$method" --header "X-API-KEY: $key" "$@" "$url/$path"
      }

      profile='[{
        "profileId": 1,
        "name": "German and English",
        "cutoff": null,
        "items": [
          { "id": 1, "language": "de", "forced": "False", "hi": "False",
            "audio_exclude": "False", "audio_only_include": "False" },
          { "id": 2, "language": "en", "forced": "False", "hi": "False",
            "audio_exclude": "False", "audio_only_include": "False" }
        ],
        "mustContain": [],
        "mustNotContain": [],
        "originalFormat": 0,
        "tag": null
      }]'
      if [ "$(api GET system/languages/profiles | jq -c 'map(del(.tag))')" != "$(jq -c 'map(del(.tag))' <<< "$profile")" ]; then
        api POST system/settings \
          --data-urlencode languages-enabled=de \
          --data-urlencode languages-enabled=en \
          --data-urlencode "languages-profiles=$profile" > /dev/null
        echo "bazarr-settings: languages and language profile updated" >&2
      fi

      assign() { # <series|movies> <id field> <form field>
        local args=()
        for id in $(api GET "$1" | jq -r --arg f "$2" '.data[] | select(.profileId == null) | .[$f]'); do
          args+=(--data-urlencode "$3=$id" --data-urlencode profileid=1)
        done
        [ "''${#args[@]}" -gt 0 ] || return 0
        api POST "$1" "''${args[@]}" > /dev/null
        echo "bazarr-settings: $1: gave $(( ''${#args[@]} / 4 )) the language profile" >&2
      }
      assign series sonarrSeriesId seriesid
      assign movies radarrId radarrid
    '';
  };
in
{
  # bazarr-api-key: a random key, so bazarr-settings can use the API.
  # bazarr-password-md5: the md5 hex of the web UI password (user aleph);
  # Bazarr compares against the hash and never sees the password itself.
  age.secrets = {
    bazarr-api-key.file = ../../../../hosts/shimmers/secrets/bazarr-api-key.age;
    bazarr-password-md5.file = ../../../../hosts/shimmers/secrets/bazarr-password-md5.age;
    bazarr-opensubtitlescom-username.file = ../../../../hosts/shimmers/secrets/bazarr-opensubtitlescom-username.age;
    bazarr-opensubtitlescom-password.file = ../../../../hosts/shimmers/secrets/bazarr-opensubtitlescom-password.age;
    bazarr-subdl-api-key.file = ../../../../hosts/shimmers/secrets/bazarr-subdl-api-key.age;
    bazarr-subsource-api-key.file = ../../../../hosts/shimmers/secrets/bazarr-subsource-api-key.age;
    radarr-api-key.file = ../../../../hosts/shimmers/secrets/radarr-api-key.age;
    sonarr-api-key.file = ../../../../hosts/shimmers/secrets/sonarr-api-key.age;
  };

  # Everything here overrides the web UI on every start (the module passes
  # it as environment). Sonarr and Radarr share the VPN namespace, hence
  # localhost; their paths are the same as Bazarr's, so no path mappings.
  # Subtitles go next to the video as .de.srt/.en.srt, where Jellyfin picks
  # them up on its next scan. Ones embedded in the video already count.
  services.bazarr = {
    enable = true;
    settings = {
      general = {
        inherit port;
        use_sonarr = true;
        use_radarr = true;
        serie_default_enabled = true;
        serie_default_profile = 1;
        movie_default_enabled = true;
        movie_default_profile = 1;
        enabled_providers = [
          "opensubtitlescom"
          "subdl"
          "subsource"
          "yifysubtitles"
          "gestdown"
        ];
      };
      auth = {
        type = "form";
        username = "aleph";
        password = secret "bazarr-password-md5";
        apikey = secret "bazarr-api-key";
      };
      sonarr = {
        ip = "127.0.0.1";
        port = 8989;
        apikey = secret "sonarr-api-key";
      };
      radarr = {
        ip = "127.0.0.1";
        port = 7878;
        apikey = secret "radarr-api-key";
      };
      opensubtitlescom = {
        username = secret "bazarr-opensubtitlescom-username";
        password = secret "bazarr-opensubtitlescom-password";
      };
      subdl.api_key = secret "bazarr-subdl-api-key";
      subsource.apikey = secret "bazarr-subsource-api-key";
    };
  };

  # Subtitle providers see the VPN's address, like the rest of the *arr
  # stack. The upstream module sets PrivateUsers=true, under which joining
  # the namespace can fail and the media group is unmapped (see slskd.nix).
  systemd.services.bazarr = {
    vpnConfinement = {
      enable = true;
      vpnNamespace = "wg";
    };
    serviceConfig.PrivateUsers = lib.mkForce false;
    unitConfig.RequiresMountsFor = [ "/mnt/chroma" ];
  };

  # Writes subtitles into media/movies and media/tv (jellyfin:media, 0775).
  users.users.bazarr.extraGroups = [ "media" ];

  # On every Bazarr start, and daily for new arrivals whose profile was
  # unset and for changes made in the web UI.
  systemd.services.bazarr-settings = {
    description = "apply the Bazarr languages kept in nix";
    after = [ "bazarr.service" ];
    wantedBy = [ "bazarr.service" ];
    startAt = "daily";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe bazarrSettings;
      LoadCredential = "apikey:${config.age.secrets.bazarr-api-key.path}";
      DynamicUser = true;
    };
  };

  my.vpn = {
    confinedServices = [ "bazarr-settings" ];
    ports = [ port ];
  };

  # Reached through the namespace's address: the port mapping is a
  # PREROUTING DNAT, which nginx's own connections never pass through.
  # Bazarr's own login guards it (form auth above).
  services.nginx.virtualHosts.${domain} = lib.recursiveUpdate (mkProxyHost { inherit port; }) {
    locations."/".proxyPass = "http://192.168.15.1:${toString port}";
  };
}
