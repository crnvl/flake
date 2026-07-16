{
  # Self-hosted RustDesk ID/rendezvous + relay server (hbbs/hbbr), running on shimmers.
  server = "shimme.rs";

  # Public key of the self-hosted signal server (hbbs), used by clients to
  # authenticate the server and encrypt the signaling channel.
  #
  # Populate this after the first deploy of shimmers by running:
  #   ssh shimmers cat /var/lib/rustdesk/id_ed25519.pub
  key = "";

  # A `rustdesk --config <string>` export string that pins every client to
  # the `server`/`key` above (ID server, relay server, key all in one).
  #
  # To generate it: install the rustdesk GUI once on any machine, go to
  # Settings > Network, unlock, manually set ID Server = server (above) and
  # Key = key (above), then click "Export Server Config" and paste the
  # resulting string here.
  configString = "";
}
