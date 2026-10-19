{
  config,
  lib,
  pkgs,
  ...
}:

let
  # The one general purpose profile, in place of picking German or Original
  # Language per request. Its language ranking lives in the custom format
  # scores, and every release lands on exactly one tier:
  #
  #   original + german  German DL                                   2000
  #                      German DL (undefined) + Not Original        2000
  #   original           nothing matches                                0
  #   german             German + Not Original                      -1000
  #   anything else      Not Original                              -10000, rejected
  #
  # Releases without a language tag count as the original language, which
  # is what radarr and sonarr fall back to when they cannot parse one.
  mainProfile = "Original + German";

  languageScores = rec {
    originalGerman = 2000;
    germanOnly = -1000;
    notOriginal = -10000;

    germanDl = originalGerman;
    germanDlUndefined = originalGerman - notOriginal;
    german = germanOnly - notOriginal;
  };

  seasonPackScore = 100;

  # Replaced by mainProfile. arr-settings moves everything off them, then
  # deletes them.
  retiredProfiles = [
    "German"
    "Original Language"
  ];

  # The arrs rank releases by quality, then custom format score, and only
  # then by the delay profile's preferred protocol, which no custom format
  # can score. Bluray and WEB therefore share one group per resolution, so
  # 1080p beats 720p, the language ranking comes next, and usenet wins over
  # an otherwise equal torrent.
  byResolution = [
    {
      name = "1080p";
      qualities = [
        "Bluray-1080p"
        "WEBDL-1080p"
        "WEBRip-1080p"
      ];
    }
    {
      name = "720p";
      qualities = [
        "Bluray-720p"
        "WEBDL-720p"
        "WEBRip-720p"
      ];
    }
  ];

  mainProfileFor =
    { until_score }:
    {
      name = mainProfile;
      reset_unmatched_scores.enabled = true;
      quality_sort = "top";
      # Lets german only releases through, other languages stay out.
      min_format_score = -5000;
      upgrade = {
        allowed = true;
        until_quality = "1080p";
        inherit until_score;
      };
      qualities = byResolution;
    };

  # What recyclarr cannot manage: delay profiles, radarr's profile language,
  # and retiring the old profiles everywhere they are referenced.
  arrSettings = pkgs.writeShellApplication {
    name = "arr-settings";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      iproute2
      jq
    ];
    text = ''
      shopt -s inherit_errexit

      radarr_url=http://localhost:7878
      sonarr_url=http://localhost:8989
      seerr_url=${lib.escapeShellArg "http://localhost:${toString config.services.seerr.port}"}
      arr_ns=wg
      seerr_settings=${lib.escapeShellArg "${lib.removeSuffix "/" (toString config.services.seerr.configDir)}/settings.json"}
      radarr_key_file=${lib.escapeShellArg config.age.secrets.radarr-api-key.path}
      sonarr_key_file=${lib.escapeShellArg config.age.secrets.sonarr-api-key.path}
      main_profile=${lib.escapeShellArg mainProfile}
      retired=${lib.escapeShellArg (builtins.toJSON retiredProfiles)}

      dry_run=false
      case "''${1:-}" in
        "") ;;
        --dry-run) dry_run=true ;;
        *) echo "usage: arr-settings [--dry-run]" >&2; exit 1 ;;
      esac

      log() { echo "arr-settings: $*" >&2; }
      die() { log "$*"; exit 1; }

      read_key() {
        [ -r "$1" ] || die "cannot read $1, run this as root"
        tr -d '[:space:]' < "$1"
      }

      radarr_key="$(read_key "$radarr_key_file")"
      sonarr_key="$(read_key "$sonarr_key_file")"
      [ -r "$seerr_settings" ] || die "cannot read $seerr_settings, run this as root"
      seerr_key="$(jq -r '.main.apiKey // empty' "$seerr_settings")"
      [ -n "$seerr_key" ] || die "no main.apiKey in $seerr_settings"

      # Same reason as in media-janitor: the arr port mappings are DNAT
      # rules that locally generated packets never pass.
      if [ ! -e "/run/netns/$arr_ns" ]; then
        log "no $arr_ns namespace, trying the host network instead"
        arr_ns=""
      fi

      # Retries only transient failures; a rejected request stays rejected.
      curl_opts=(
        --fail-with-body --silent --show-error --location --max-time 120
        --retry 2 --retry-delay 2 --retry-connrefused
      )

      # call <netns or ""> <auth header> <method> <url> [json body]
      # Prints the response; on failure the response goes to stderr.
      call() {
        local ns=$1 auth=$2 method=$3 url=$4 out
        if [ "$method" != GET ] && [ "$dry_run" = true ]; then
          log "dry run, would $method $url"
          return 0
        fi
        local args=("''${curl_opts[@]}" --request "$method" --header "$auth")
        if [ "$#" -ge 5 ]; then
          args+=(--header "Content-Type: application/json" --data-binary "$5")
        fi
        if [ -n "$ns" ]; then
          out="$(ip netns exec "$ns" curl "''${args[@]}" "$url")" || { printf '%s\n' "$out" >&2; return 1; }
        else
          out="$(curl "''${args[@]}" "$url")" || { printf '%s\n' "$out" >&2; return 1; }
        fi
        printf '%s' "$out"
      }

      arr() { # <radarr|sonarr> <method> <path> [json body]
        local url key
        case "$1" in
          radarr) url=$radarr_url key=$radarr_key ;;
          sonarr) url=$sonarr_url key=$sonarr_key ;;
        esac
        call "$arr_ns" "X-Api-Key: $key" "$2" "$url/api/v3/$3" "''${@:4}"
      }

      seerr() { # <method> <path> [json body]
        call "" "X-Api-Key: $seerr_key" "$1" "$seerr_url/api/v1/$2" "''${@:3}"
      }

      # Usenet first, torrent as the fallback, no delay on either. The arrs
      # default to this, so it only corrects drift from the web UI.
      prefer_usenet() { # <app>
        local profiles p
        profiles="$(arr "$1" GET delayprofile | jq -c '
          .[]
          | select(.preferredProtocol != "usenet" or .enableUsenet != true or .enableTorrent != true
                   or .usenetDelay != 0 or .torrentDelay != 0)
          | .preferredProtocol = "usenet"
          | .enableUsenet = true
          | .enableTorrent = true
          | .usenetDelay = 0
          | .torrentDelay = 0')"
        while read -r p; do
          [ -n "$p" ] || continue
          arr "$1" PUT "delayprofile/$(jq -r .id <<< "$p")" "$p" > /dev/null
          log "$1: delay profile $(jq -r .id <<< "$p") now prefers usenet, torrent as fallback"
        done <<< "$profiles"
      }

      # Radarr profiles also filter on a single language, and new ones start
      # out as "Original", which would drop german only releases before the
      # custom formats get to rank them. Sonarr has no such setting.
      any_language() {
        local profile
        profile="$(arr radarr GET qualityprofile | jq -c --arg n "$main_profile" '
          .[] | select(.name == $n and .language.id != -1) | .language = { id: -1, name: "Any" }')"
        [ -n "$profile" ] || return 0
        arr radarr PUT "qualityprofile/$(jq -r .id <<< "$profile")" "$profile" > /dev/null
        log "radarr: $main_profile now takes any language and leaves the ranking to its custom formats"
      }

      # Points seerr's defaults and override rules away from the retired
      # profiles, so new requests do not hit a profile that is gone.
      seerr_retire() { # <app> <main id> <retired ids json>
        local app=$1 main=$2 old=$3 field type servers rules pending skip=0 page s r id
        case "$app" in
          radarr) field=radarrServiceId type=movie ;;
          sonarr) field=sonarrServiceId type=tv ;;
        esac

        servers="$(seerr GET "settings/$app" | jq -c --argjson old "$old" --argjson p "$main" --arg n "$main_profile" '
          .[]
          | select((.activeProfileId | IN($old[])) or (.activeAnimeProfileId | IN($old[])))
          | if .activeProfileId | IN($old[]) then .activeProfileId = $p | .activeProfileName = $n else . end
          | if .activeAnimeProfileId | IN($old[]) then .activeAnimeProfileId = $p | .activeAnimeProfileName = $n else . end')"
        while read -r s; do
          [ -n "$s" ] || continue
          # Seerr validates the body against its OpenAPI spec, where the id
          # is read-only and several fields are not nullable, so send it the
          # way its own settings page does: no id, unset fields left out.
          seerr PUT "settings/$app/$(jq -r .id <<< "$s")" \
            "$(jq -c 'del(.id) | with_entries(select(.value != null))' <<< "$s")" > /dev/null
          log "seerr: $(jq -r .name <<< "$s") now requests $main_profile"
        done <<< "$servers"

        # A rule that only picked one of the old profiles has nothing left to
        # do; one that also sets a root folder or tags keeps those.
        rules="$(seerr GET overrideRule | jq -c --arg f "$field" --argjson old "$old" '
          .[] | select(.[$f] != null and (.profileId | IN($old[])))')"
        while read -r r; do
          [ -n "$r" ] || continue
          id="$(jq -r .id <<< "$r")"
          if jq -e '(.rootFolder // "") == "" and (.tags // "") == ""' <<< "$r" > /dev/null; then
            seerr DELETE "overrideRule/$id" > /dev/null
            log "seerr: dropped override rule $id, it only picked a retired profile"
          else
            seerr PUT "overrideRule/$id" "$(jq -c '{ users, genre, language, keywords, profileId: null,
              rootFolder, tags, radarrServiceId, sonarrServiceId }' <<< "$r")" > /dev/null
            log "seerr: override rule $id no longer picks a profile"
          fi
        done <<< "$rules"

        # Pending requests carry the profile they were made with, and the
        # seerr API cannot safely rewrite that for series, so just say so.
        pending=""
        while : ; do
          page="$(seerr GET "request?filter=pending&take=100&skip=$skip")"
          pending+="$(jq -c --arg t "$type" --argjson old "$old" '
            .results[] | select(.type == $t and (.profileId | IN($old[])))' <<< "$page")"$'\n'
          [ "$(jq '.results | length' <<< "$page")" -eq 100 ] || break
          skip=$(( skip + 100 ))
        done
        while read -r r; do
          [ -n "$r" ] || continue
          log "seerr: pending request $(jq -r .id <<< "$r") asks for a retired $app profile, pick $main_profile when approving it"
        done <<< "$pending"
      }

      retire() { # <app>
        local app=$1 profiles old ids main kind field items lists cols p
        profiles="$(arr "$app" GET qualityprofile)"
        old="$(jq -c --argjson names "$retired" 'map(select(.name | IN($names[])) | { id, name })' <<< "$profiles")"
        [ "$(jq length <<< "$old")" -gt 0 ] || return 0
        main="$(jq --arg n "$main_profile" 'map(select(.name == $n)) | first | .id // empty' <<< "$profiles")"
        if [ -z "$main" ]; then
          log "$app: no $main_profile profile yet, keeping $(jq -r 'map(.name) | join(" and ")' <<< "$old") until recyclarr has created it"
          return 0
        fi
        ids="$(jq -c 'map(.id)' <<< "$old")"

        case "$app" in
          radarr) kind=movie field=movieIds ;;
          sonarr) kind=series field=seriesIds ;;
        esac
        items="$(arr "$app" GET "$kind" | jq -c --argjson old "$ids" 'map(select(.qualityProfileId | IN($old[])) | .id)')"
        if [ "$(jq length <<< "$items")" -gt 0 ]; then
          arr "$app" PUT "$kind/editor" "$(jq -nc --arg f "$field" --argjson ids "$items" --argjson p "$main" \
            '{ ($f): $ids, qualityProfileId: $p, moveFiles: false }')" > /dev/null
          log "$app: moved $(jq length <<< "$items") $kind entries to $main_profile"
        fi

        lists="$(arr "$app" GET importlist | jq -c --argjson old "$ids" --argjson p "$main" '
          .[] | select(.qualityProfileId | IN($old[])) | .qualityProfileId = $p')"
        while read -r p; do
          [ -n "$p" ] || continue
          arr "$app" PUT "importlist/$(jq -r .id <<< "$p")?forceSave=true" "$p" > /dev/null
          log "$app: import list $(jq -r .name <<< "$p") now adds to $main_profile"
        done <<< "$lists"

        if [ "$app" = radarr ]; then
          cols="$(arr radarr GET collection | jq -c --argjson old "$ids" 'map(select(.qualityProfileId | IN($old[])) | .id)')"
          if [ "$(jq length <<< "$cols")" -gt 0 ]; then
            arr radarr PUT collection "$(jq -nc --argjson ids "$cols" --argjson p "$main" \
              '{ collectionIds: $ids, qualityProfileId: $p }')" > /dev/null
            log "radarr: moved $(jq length <<< "$cols") collections to $main_profile"
          fi
        fi

        # Before deleting, so a seerr failure leaves the old profiles (and
        # their ids, which seerr refers to) around for the next run.
        seerr_retire "$app" "$main" "$ids"

        while read -r p; do
          arr "$app" DELETE "qualityprofile/$(jq -r .id <<< "$p")" > /dev/null
          log "$app: removed the $(jq -r .name <<< "$p") profile"
        done <<< "$(jq -c '.[]' <<< "$old")"
      }

      for app in radarr sonarr; do
        prefer_usenet "$app"
      done
      any_language
      for app in radarr sonarr; do
        retire "$app"
      done
    '';
  };

  hd1080 = [
    { name = "Bluray-1080p"; }
    {
      name = "WEB 1080p";
      qualities = [
        "WEBDL-1080p"
        "WEBRip-1080p"
      ];
    }
    { name = "Bluray-720p"; }
    {
      name = "WEB 720p";
      qualities = [
        "WEBDL-720p"
        "WEBRip-720p"
      ];
    }
  ];

  uhd2160 = [
     { name = "Bluray-2160p"; }
     {
       name = "WEB 2160p";
       qualities = [
         "WEBDL-2160p"
         "WEBRip-2160p"
       ];
     }
   ]
   ++ hd1080;
in
{
  age.secrets = {
    radarr-api-key.file = ../../../../hosts/shimmers/secrets/radarr-api-key.age;
    sonarr-api-key.file = ../../../../hosts/shimmers/secrets/sonarr-api-key.age;
  };

  services.recyclarr = {
    enable = true;
    schedule = "daily";
    configuration = {
      radarr.movies = {
        base_url = "http://localhost:7878";
        api_key._secret = config.age.secrets.radarr-api-key.path;

        quality_profiles = [
          (mainProfileFor {
            until_score = languageScores.originalGerman;
          })
        ];

        custom_formats = [
          {
            trash_ids = [ "f845be10da4f442654c13e1f2c3d6cd5" ]; # German DL
            assign_scores_to = [
              {
                name = mainProfile;
                score = languageScores.germanDl;
              }
            ];
          }
          {
            trash_ids = [ "6aad77771dabe9d3e9d7be86f310b867" ]; # German DL (undefined)
            assign_scores_to = [
              {
                name = mainProfile;
                score = languageScores.germanDlUndefined;
              }
            ];
          }
          {
            trash_ids = [ "86bc3115eb4e9873ac96904a4a68e19e" ]; # German
            assign_scores_to = [
              {
                name = mainProfile;
                score = languageScores.german;
              }
            ];
          }
          {
            trash_ids = [ "d6e9318c875905d6cfb5bee961afcea9" ]; # Language: Not Original
            assign_scores_to = [
              {
                name = mainProfile;
                score = languageScores.notOriginal;
              }
            ];
          }
        ];
      };

      sonarr.tv = {
        base_url = "http://localhost:8989";
        api_key._secret = config.age.secrets.sonarr-api-key.path;

        quality_profiles = [
          (mainProfileFor {
            # Keeps upgrading single episodes to a season pack, as the old
            # profiles did.
            until_score = languageScores.originalGerman + seasonPackScore;
          })
          {
            trash_id = "20e0fc959f1f1704bed501f23bdae76f"; # [Anime] Remux-1080p
            name = "Anime";
            reset_unmatched_scores.enabled = true;
            quality_sort = "top";
            upgrade = {
              allowed = true;
              until_quality = "Bluray-1080p";
              until_score = 10000;
            };
            qualities = hd1080;
          }
        ];

        custom_formats = [
          {
            trash_ids = [ "ed51973a811f51985f14e2f6f290e47a" ]; # German DL
            assign_scores_to = [
              {
                name = mainProfile;
                score = languageScores.germanDl;
              }
            ];
          }
          {
            trash_ids = [ "c5dd0fd675f85487ad5bdf97159180bd" ]; # German DL (undefined)
            assign_scores_to = [
              {
                name = mainProfile;
                score = languageScores.germanDlUndefined;
              }
            ];
          }
          {
            trash_ids = [ "8a9fcdbb445f2add0505926df3bb7b8a" ]; # German
            assign_scores_to = [
              {
                name = mainProfile;
                score = languageScores.german;
              }
            ];
          }
          {
            trash_ids = [ "3bc5f395426614e155e585a2f056cdf1" ]; # Season Pack
            assign_scores_to = [
              {
                name = mainProfile;
                score = seasonPackScore;
              }
              {
                name = "Anime";
                score = 10;
              }
            ];
          }
          {
            trash_ids = [ "ae575f95ab639ba5d15f663bf019e3e8" ]; # Language: Not Original
            assign_scores_to = [
              {
                name = mainProfile;
                score = languageScores.notOriginal;
              }
            ];
          }
        ];
      };
    };
  };

  my.vpn.confinedServices = [ "recyclarr" ];

  # Runs after every recyclarr sync, which is when a newly created profile
  # first exists. Root, for the seerr key in its state directory and for
  # entering the vpn namespace.
  systemd.services.arr-settings = {
    description = "apply the radarr, sonarr and seerr settings recyclarr cannot manage";
    after = [ "recyclarr.service" ];
    wantedBy = [ "recyclarr.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe arrSettings;
    };
  };

  environment.systemPackages = [
    config.services.recyclarr.package
    arrSettings
  ];
}
