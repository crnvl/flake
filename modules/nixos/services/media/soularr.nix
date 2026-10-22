{ config, pkgs, ... }:

let
  slskdDownloads = config.services.slskd.settings.directories.downloads;
  slskdUid = toString config.users.users.slskd.uid;
  slskdGid = toString config.users.groups.slskd.gid;

  # soularr reads this with an env-var-expanding ConfigParser, so the API keys
  # come from the container's --env-file and never touch the nix store.
  # slskd and lidarr see the downloads dir under the same path, so both
  # download_dir values match.
  configFile = pkgs.writeText "soularr-config.ini" ''
    [Lidarr]
    api_key = $LIDARR_API_KEY
    host_url = http://127.0.0.1:8686
    download_dir = ${slskdDownloads}
    disable_sync = False

    [Slskd]
    api_key = $SLSKD_API_KEY
    host_url = http://127.0.0.1:5030
    url_base = /
    download_dir = ${slskdDownloads}
    delete_searches = False
    # Despite the name, a total limit counted from when an album is queued,
    # progress or not. Slow uploaders (~100 KiB/s is common) need more than
    # the default hour for a FLAC album. soularr starts no new searches
    # until its current batch finishes, so this is also the longest new
    # requests can be held up.
    stalled_timeout = 10800
    # How long an album may sit entirely in the peer's upload queue before
    # it is cancelled. Queues are normal on Soulseek; at the default 300
    # every busy uploader got cancelled, and the next run usually picked
    # the same one again, landing at the back of its queue.
    remote_queue_timeout = 1800

    [Release Settings]
    use_selected_lidarr_release = False
    use_most_common_tracknum = True
    allow_multi_disc = True
    accepted_countries = Europe,Germany,Japan,United Kingdom,United States,[Worldwide],Australia,Canada
    skip_region_check = False
    accepted_formats = CD,Digital Media,Vinyl

    [Search Settings]
    search_timeout = 5000
    maximum_peer_queue = 50
    minimum_peer_upload_speed = 0
    minimum_filename_match_ratio = 0.8
    minimum_search_interval = 5
    allowed_filetypes = flac 24/192,flac 16/44.1,flac,mp3 320,mp3
    ignored_users =
    album_prepend_artist = False
    search_type = incrementing_page
    number_of_albums_to_grab = 10
    title_blacklist =
    search_blacklist =
    search_source = missing
    failed_import_denylist = True

    [Download Settings]
    download_filtering = True
    use_extension_whitelist = False
    extensions_whitelist = lrc,nfo,txt
    rename_download_folders = True

    [Logging]
    level = INFO
    format = [%(levelname)s|%(module)s|L%(lineno)d] %(asctime)s: %(message)s
    datefmt = %Y-%m-%dT%H:%M:%S%z
    # Also in journald; the file is what the web UI's log viewer reads.
    log_to_file = True
    log_file = soularr.log
    max_bytes = 1048576
    backup_count = 3
  '';
in
{
  # Contains LIDARR_API_KEY=... (same value as LIDARR__AUTH__APIKEY in
  # lidarr-env) and SLSKD_API_KEY=... (same as in slskd-env).
  age.secrets.soularr-env.file = ../../../../hosts/shimmers/secrets/soularr-env.age;

  virtualisation.oci-containers.containers.soularr = {
    image = "ghcr.io/mrusse/soularr:latest";
    # Same uid as slskd so it can retag/rename the downloads it moves around;
    # new dirs inherit the media group from the setgid downloads dir.
    user = "${slskdUid}:${slskdGid}";
    ports = [ ];
    extraOptions = [
      "--network=host"
      # Group-writable dirs so lidarr can move files out on import.
      "--umask=0002"
    ];
    environment = {
      TZ = config.time.timeZone;
      SCRIPT_INTERVAL = "300";
      WEBUI_ENABLED = "true";
    };
    environmentFiles = [ config.age.secrets.soularr-env.path ];
    volumes = [
      "/var/lib/soularr:/data"
      "${configFile}:/data/config.ini:ro"
      "${slskdDownloads}:${slskdDownloads}"
    ];
  };

  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  # Join the wg netns so it reaches lidarr/slskd over localhost, same as
  # decluttarr.
  my.vpn = {
    confinedServices = [ "podman-soularr" ];
    # Web UI (logs, failed-import denylist).
    ports = [ 8265 ];
  };

  systemd.services.podman-soularr = {
    after = [
      "lidarr.service"
      "slskd.service"
    ];
    wants = [
      "lidarr.service"
      "slskd.service"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/soularr 0750 slskd slskd -"
  ];
}
