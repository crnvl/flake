{ ... }:

# F-Droid repo for the patched Journal APKs (https://git.gay/67/journal).
# Static files only: the repo is built and signed on the laptop with
# `fdroid update` and rsynced here by the journal repo's publish-fdroid.sh,
# so the signing key never touches this host. Repo URL for clients:
# https://fdroid.shimme.rs/repo
let
  domain = "fdroid.shimme.rs";
  root = "/var/lib/fdroid";
in
{
  # Owned by aleph so the publish script can rsync straight in over SSH.
  systemd.tmpfiles.rules = [ "d ${root} 0755 aleph users -" ];

  services.nginx.virtualHosts.${domain} = {
    enableACME = true;
    forceSSL = true;
    inherit root;
    locations."= /".return = "302 /repo/";
    # Indexes change on every publish; APKs never change under the same name.
    locations."~ ^/(repo|archive)/(index|entry)[^/]*$".extraConfig = ''
      add_header Cache-Control "no-cache";
    '';
  };
}
