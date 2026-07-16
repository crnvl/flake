{ ... }:

{
  services.rustdesk-server = {
    enable = true;
    openFirewall = true;

    signal.relayHosts = [ "shimme.rs" ];

    signal.extraArgs = [ "-k" "_" ];
    relay.extraArgs = [ "-k" "_" ];
  };
}
