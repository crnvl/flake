{ lib, pkgs, ... }:

{
  services.sabnzbd = {
    enable = true;
    allowConfigWrite = true;
    # Everything it writes is group media, so the arrs and aurral can move,
    # retag and delete it. A supplementary group isn't enough: sabnzbd sets
    # its job dirs to 775, which drops the setgid bit, so folders unpacked
    # inside a job came out sabnzbd:sabnzbd and aurral got EACCES on them.
    group = "media";
  };

  systemd.services.sabnzbd.serviceConfig.ExecStart =
    lib.mkForce "${lib.getBin pkgs.sabnzbd}/bin/sabnzbd -d -f /var/lib/sabnzbd/sabnzbd.ini -s 0.0.0.0:8080 -b 0";

  systemd.services.sabnzbd.vpnConfinement = {
    enable = true;
    vpnNamespace = "wg";
  };

  my.vpn.portMappings = [
    {
      from = 8080;
      to = 8080;
    }
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/sabnzbd/downloads 0775 sabnzbd media -"
    "d /var/lib/sabnzbd/downloads/radarr 0775 sabnzbd media -"
    "d /var/lib/sabnzbd/downloads/sonarr 0775 sabnzbd media -"
    "d /var/lib/sabnzbd/downloads/lidarr 0775 sabnzbd media -"
    # aurral's category. setgid so job dirs stay in media: aurral moves the
    # finished files out and retags them in place (see aurral.nix).
    # aurral grabs a whole album for one playlist track and often leaves the
    # rest behind, so anything untouched for two weeks is removed.
    "d /var/lib/sabnzbd/downloads/aurral 2775 sabnzbd media 14d"
    "d /var/lib/sabnzbd/incomplete 0755 sabnzbd media -"
  ];
}
