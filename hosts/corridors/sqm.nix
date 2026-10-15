{ pkgs, ... }:

# CAKE traffic shaping (SQM) for the Vodafone cable line.
#
# The modem has huge buffers: with the upload saturated, ping went to 1-2.4 s
# (with loss); with the download saturated, +90 ms. Shaping just below the line
# rate keeps the queue here, where CAKE gives sparse flows (games, voice)
# priority over bulk transfers. Measured 2026-10-15 with both directions
# saturated: ping p50/p99 went from ~670 ms / 2.3 s (10% loss) to ~30 / 45-90 ms.
#
# Only frames to/from the router's MAC (= internet traffic) are shaped, so LAN
# traffic such as WiVRn to the headset still runs at full speed.
#
# Disable temporarily with `systemctl stop sqm`.

let
  dev = "enp2s0";
  ifb = "ifb4${dev}";

  # The line delivers ~190 Mbit/s down and 17-22 Mbit/s up (the upstream is
  # shared with the neighbourhood and drops in busy hours). 18 Mbit/s up still
  # spiked to 400-650 ms at times; 15 held. Re-measure if the plan changes.
  upload = "15mbit";
  download = "170mbit";

  cleanup = ''
    tc qdisc del dev ${dev} root 2>/dev/null || true
    tc qdisc del dev ${dev} ingress 2>/dev/null || true
    ip link del ${ifb} 2>/dev/null || true
  '';
in
{
  systemd.services.sqm = {
    description = "CAKE traffic shaping on ${dev}";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    path = with pkgs; [
      gawk
      iproute2
      iputils
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "10s";
    };

    script = ''
      # The router's MAC tells internet traffic apart from LAN traffic.
      gw=$(ip -4 route show default dev ${dev} | awk '{ print $3; exit }')
      [ -n "$gw" ] || { echo "no default route on ${dev}" >&2; exit 1; }
      ping -c 1 -W 1 "$gw" >/dev/null 2>&1 || true
      gwmac=$(ip -4 neigh show "$gw" dev ${dev} \
        | awk '{ for (i = 1; i < NF; i++) if ($i == "lladdr") { print $(i + 1); exit } }')
      [ -n "$gwmac" ] || { echo "no MAC for gateway $gw" >&2; exit 1; }
      echo "shaping traffic via $gw ($gwmac): up ${upload}, down ${download}"

      ${cleanup}

      # Egress: band 1:1 (to the router) goes through CAKE, band 1:2 (LAN) doesn't.
      tc qdisc add dev ${dev} root handle 1: prio bands 2 priomap 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
      tc qdisc add dev ${dev} parent 1:1 cake bandwidth ${upload} docsis ack-filter
      tc qdisc add dev ${dev} parent 1:2 fq_codel
      tc filter add dev ${dev} parent 1: protocol all prio 1 \
        flower dst_mac "$gwmac" classid 1:1

      # Ingress: frames from the router are redirected through an IFB running CAKE.
      ip link add ${ifb} type ifb
      ip link set ${ifb} up
      tc qdisc add dev ${ifb} root cake bandwidth ${download} docsis ingress
      tc qdisc add dev ${dev} handle ffff: ingress
      tc filter add dev ${dev} parent ffff: protocol all prio 1 \
        flower src_mac "$gwmac" action mirred egress redirect dev ${ifb}
    '';

    preStop = cleanup;
  };
}
