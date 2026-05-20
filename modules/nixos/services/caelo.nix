{
  config,
  pkgs,
  inputs,
  ...
}:

let
  caelo-src = inputs.caelo;
in
{
  # MinIO is marked insecure in nixpkgs-unstable
  nixpkgs.config.permittedInsecurePackages = [
    "minio-2025-10-15T17-29-55Z"
  ];

  # --- SSH (let root use aleph's key for fetching the private repo) ---
  programs.ssh.extraConfig = ''
    Host github.com
      IdentityFile /home/aleph/.ssh/id_ed25519
  '';

  # --- Secrets ---
  age.secrets."caelo-env" = {
    file = ../../../hosts/shimmers/secrets/caelo-env.age;
    mode = "0440";
  };

  # --- PostgreSQL ---
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    extensions = ps: [ ps.pgvector ];
    ensureDatabases = [ "caelo" ];
    ensureUsers = [
      {
        name = "caelo";
        ensureDBOwnership = true;
      }
    ];
    # mkBefore ensures our trust rules come before the default md5 rules
    authentication = pkgs.lib.mkBefore ''
      local caelo caelo trust
      host caelo caelo 127.0.0.1/32 trust
    '';
  };

  # --- Redis ---
  services.redis.servers.caelo = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";
  };

  # --- MinIO ---
  services.minio = {
    enable = true;
    listenAddress = "127.0.0.1:9000";
    consoleAddress = "127.0.0.1:9001";
    dataDir = [ "/var/lib/minio/data" ];
  };

  # --- Build images from source ---
  systemd.services.caelo-build-images = {
    description = "Build Caelo OCI images from source";
    after = [ "network.target" ];
    before = [
      "podman-caelo-webapp.service"
      "podman-caelo-worker.service"
      "podman-caelo-socket.service"
    ];
    requiredBy = [
      "podman-caelo-webapp.service"
      "podman-caelo-worker.service"
      "podman-caelo-socket.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [
      podman
      coreutils
    ];
    script = ''
      set -euo pipefail

      echo "Building caelo-webapp image..."
      podman build --no-cache -t localhost/caelo-webapp:latest -f ${caelo-src}/webapp/Dockerfile ${caelo-src}

      echo "Building caelo-worker image..."
      podman build --no-cache -t localhost/caelo-worker:latest -f ${caelo-src}/worker/Dockerfile ${caelo-src}

      echo "Building caelo-socket image..."
      podman build --no-cache -t localhost/caelo-socket:latest -f ${caelo-src}/socket/Dockerfile ${caelo-src}

      echo "All caelo images built successfully."
    '';
  };

  # --- OCI Containers ---
  virtualisation.oci-containers.containers = {
    caelo-webapp = {
      image = "localhost/caelo-webapp:latest";
      extraOptions = [
        "--network=host"
        "--pull=never"
      ];
      environmentFiles = [ config.age.secrets."caelo-env".path ];
    };

    caelo-worker = {
      image = "localhost/caelo-worker:latest";
      extraOptions = [
        "--network=host"
        "--pull=never"
      ];
      environmentFiles = [ config.age.secrets."caelo-env".path ];
    };

    caelo-socket = {
      image = "localhost/caelo-socket:latest";
      extraOptions = [
        "--network=host"
        "--pull=never"
      ];
      environmentFiles = [ config.age.secrets."caelo-env".path ];
    };
  };

  # --- Systemd ordering ---
  systemd.services.podman-caelo-webapp = {
    after = [
      "postgresql.service"
      "redis-caelo.service"
      "minio.service"
      "caelo-build-images.service"
    ];
    requires = [
      "postgresql.service"
      "redis-caelo.service"
      "minio.service"
      "caelo-build-images.service"
    ];
  };

  systemd.services.podman-caelo-worker = {
    after = [
      "postgresql.service"
      "redis-caelo.service"
      "caelo-build-images.service"
    ];
    requires = [
      "postgresql.service"
      "redis-caelo.service"
      "caelo-build-images.service"
    ];
  };

  systemd.services.podman-caelo-socket = {
    after = [
      "redis-caelo.service"
      "caelo-build-images.service"
    ];
    requires = [
      "redis-caelo.service"
      "caelo-build-images.service"
    ];
  };

  # --- Nginx ---
  services.nginx.virtualHosts = {
    "caelo.shimme.rs" = {
      enableACME = true;
      forceSSL = true;

      locations."/api/socket/" = {
        proxyPass = "http://127.0.0.1:3002";
        proxyWebsockets = true;
      };

      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
      };
    };

    "cdn.caelo.shimme.rs" = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:9000";
      };
    };
  };
}
