{ config, ... }:

{
  services.monero = {
    enable = true;

    rpc = {
      address = "127.0.0.1";
      port = 18089;
    };
  };

  environmentFile = config.age.secrets.monero-rpc.path;

  extraConfig = ''
    restricted-rpc=1
    prune-blockchain=1
    sync-pruned-blocks=1
    tx-proxy=tor,127.0.0.1:9050,16
    no-igd=1
    enable-dns-blocklist=1
    pad-transactions=1
  '';

  systemd.services.monero.after = [ "tor.service" ];

  services.tor = {
    enable = true;
    client.enable = true;

    relay.onionServices."monero-rpc" = {
      version = 3;
      map = [
        {
          port = 18089;
          target = {
            addr = "127.0.0.1";
            port = 18089;
          };
        }
      ];
    };
  };
}
