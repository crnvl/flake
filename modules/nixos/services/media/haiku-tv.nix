# 大雨-Ooame: Haiku as a 24/7 Jellyfin Live TV channel.
#
# The service comes from the unuo flake input: it plays the generative album
# headless and serves an M3U playlist, an XMLTV guide and the live H.264/AAC
# MPEG-TS stream on localhost. ffmpeg only runs while someone is watching;
# the piece re-arranges itself every 10 minutes (one guide entry each) and
# the sample banks are regenerated daily, all in /var/lib/haiku-tv.
#
# One-time Jellyfin setup (Dashboard -> Live TV):
#   Tuner Devices: add an "M3U Tuner" with
#     http://127.0.0.1:8740/haiku.m3u
#   TV Guide Data Providers: add "XMLTV" with
#     http://127.0.0.1:8740/epg.xml
#   (the channel is matched to its guide by tvg-id "haiku").
{ ... }:

{
  services.haiku-tv = {
    enable = true;
    listenAddr = "127.0.0.1:8740";
  };
}
