{ ... }:

# exo: zero-install, end-to-end encrypted, peer-to-peer file transfer.
# The module (from the exo flake) runs the signaling server, puts nginx + ACME
# in front with access logging off, and runs a STUN-only coturn on 3478 so no
# third party learns users' IPs. No TURN relay: transfers between networks
# that can't connect directly fail rather than being relayed.
{
  services.exo = {
    enable = true;
    domain = "share.shimme.rs";
    listen = "127.0.0.1:3090";
    stun.enable = true;
  };
}
