{ config, ... }:

{
  imports = [
    ./disk-config.nix

    ../../modules/nixos/boxes/chroma.nix

    ../../modules/nixos/services/nginx.nix
    ../../modules/nixos/services/kanidm.nix
    ../../modules/nixos/services/monitoring
    ../../modules/nixos/services/jellyfin.nix

    ../../modules/nixos/services/transmission.nix
    ../../modules/nixos/services/qbittorrent.nix

    ../../modules/nixos/services/vpn.nix
    ../../modules/nixos/services/monero.nix
    ../../modules/nixos/services/vaultwarden.nix
    ../../modules/nixos/services/nextcloud.nix
    ../../modules/nixos/services/beat.nix
    ../../modules/nixos/services/mail.nix

    ../../modules/nixos/services/media/sabnzbd.nix
    ../../modules/nixos/services/media/prowlarr.nix
    ../../modules/nixos/services/media/sonarr.nix
    ../../modules/nixos/services/media/radarr.nix
    ../../modules/nixos/services/media/seerr.nix
    ../../modules/nixos/services/media/seerr-usage.nix
    ../../modules/nixos/services/media/janitor.nix
    ../../modules/nixos/services/media/byparr.nix
    ../../modules/nixos/services/media/recyclarr.nix
    ../../modules/nixos/services/media/tunarr.nix
    ../../modules/nixos/services/media/tagesschau.nix
    ../../modules/nixos/services/media/decluttarr.nix

    ../../modules/nixos/services/catshift.nix
    ../../modules/nixos/services/proxyagain.nix
  ];

  system.stateVersion = "26.05";

  my.mediaJanitor.dryRun = false;
  networking = {
    hostName = "shimmers";
    hosts = {
      "127.0.0.1" = [ "id.shimme.rs" ];
    };
  };

  # Read-only deploy key so `nixos-rebuild` can fetch the private proxyagain
  # flake input over SSH. Only usable for that one repo.
  #
  # This is scoped to a dedicated "git-gay-proxyagain" host alias (matching
  # the flake input's URL in flake.nix), rather than "git.gay" itself, so it
  # only ever applies to that one fetch. A blanket "Host git.gay" override
  # would hijack every other SSH connection to git.gay too - including this
  # flake repo's own `git pull` - and this deploy key isn't authorized for
  # any of those.
  #
  # Bootstrapping note: agenix only decrypts secrets to /run/agenix during
  # system activation, which happens *after* the flake has already been
  # evaluated (and its inputs fetched). So the very first switch that
  # introduces this secret needs it pre-placed manually - see the flake repo
  # notes for the one-time bootstrap command. Every switch after that (and
  # every reboot) is handled automatically by agenix.
  #
  # Group is "wheel", not "root": `nixos-rebuild switch` invoked via plain
  # `sudo` builds/evaluates as the original calling user (only the final
  # activation runs as root), so the key must be readable by aleph too. This
  # adds no real exposure since wheel members already have unrestricted root
  # via sudo anyway.
  age.secrets.proxyagain-deploy-key = {
    file = ./secrets/proxyagain-deploy-key.age;
    owner = "root";
    group = "wheel";
    mode = "0440";
  };

  programs.ssh.extraConfig = ''
    Host git-gay-proxyagain
      HostName git.gay
      User git
      IdentityFile ${config.age.secrets.proxyagain-deploy-key.path}
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
  '';
}
