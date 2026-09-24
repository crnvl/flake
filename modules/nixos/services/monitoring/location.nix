{
  config,
  pkgs,
  mkProxyHost,
  ...
}:

let
  domain = "loc.shimme.rs";

  # Receives GPSLogger "Custom URL" pings and writes them into
  # victoriametrics with their real fix timestamps, next to the oura data:
  #
  #   GET /log?lat=..&lon=..&acc=..&alt=..&spd=..&batt=..&time=<epoch>
  #
  # Auth is HTTP Basic (GPSLogger supports it natively); credentials and the
  # optional home coordinates live in the location-env agenix secret, so
  # nothing sensitive lands in the (public) repo or the nix store. When home
  # coordinates are set, a derived location_home 0/1 gauge is emitted too, so
  # dashboards can show "Home"/"Away" without exposing raw coordinates.
  ingestServer = pkgs.writers.writePython3Bin "location-ingest" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ''
    import base64
    import hmac
    import math
    import os
    import sys
    import time
    import urllib.parse
    import urllib.request
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    VM_URL = "http://127.0.0.1:8428/api/v1/import/prometheus"
    LISTEN = ("127.0.0.1", 3083)

    USER = os.environ.get("LOCATION_USER", "phone")
    PASSWORD = os.environ["LOCATION_PASSWORD"]
    HOME_LAT = os.environ.get("HOME_LAT")
    HOME_LON = os.environ.get("HOME_LON")
    HOME_RADIUS = float(os.environ.get("HOME_RADIUS_METERS", "200"))

    METRICS = {
        "lat": "location_latitude",
        "lon": "location_longitude",
        "acc": "location_accuracy_meters",
        "alt": "location_altitude_meters",
        "spd": "location_speed_mps",
        "batt": "phone_battery_percent",
    }


    def haversine_m(lat1, lon1, lat2, lon2):
        p1, p2 = math.radians(lat1), math.radians(lat2)
        dp = p2 - p1
        dl = math.radians(lon2 - lon1)
        a = (math.sin(dp / 2) ** 2
             + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2)
        return 2 * 6371000.0 * math.asin(math.sqrt(a))


    class Handler(BaseHTTPRequestHandler):
        server_version = "location-ingest"

        def log_message(self, fmt, *args):
            # The default logger prints the full request line, which would
            # put coordinates into the journal. Stay quiet instead.
            pass

        def _reply(self, code, body):
            data = body.encode()
            self.send_response(code)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _authed(self):
            header = self.headers.get("Authorization", "")
            if not header.startswith("Basic "):
                return False
            try:
                creds = base64.b64decode(header[6:]).decode()
            except Exception:
                return False
            want = f"{USER}:{PASSWORD}"
            return hmac.compare_digest(creds.encode(), want.encode())

        def do_POST(self):
            self.do_GET()

        def do_GET(self):
            url = urllib.parse.urlparse(self.path)
            if url.path != "/log":
                self._reply(404, "not found\n")
                return
            if not self._authed():
                self.send_response(401)
                self.send_header("WWW-Authenticate", 'Basic realm="location"')
                self.end_headers()
                return

            q = urllib.parse.parse_qs(url.query)

            def num(key):
                try:
                    return float(q[key][0])
                except (KeyError, IndexError, ValueError):
                    return None

            # GPSLogger's %TIMESTAMP is epoch seconds; fall back to "now"
            # for anything missing or implausible.
            ts = num("time")
            if ts is None or not (0 < ts < 4102444800):
                ts = time.time()
            ts_ms = int(ts * 1000)

            lines = []
            for key, metric in METRICS.items():
                v = num(key)
                if v is not None:
                    lines.append(f"{metric} {v} {ts_ms}")

            lat, lon = num("lat"), num("lon")
            if HOME_LAT and HOME_LON and lat is not None and lon is not None:
                d = haversine_m(lat, lon, float(HOME_LAT), float(HOME_LON))
                home = 1 if d <= HOME_RADIUS else 0
                lines.append(f"location_home {home} {ts_ms}")

            if not lines:
                self._reply(400, "no usable fields\n")
                return

            body = ("\n".join(lines) + "\n").encode()
            req = urllib.request.Request(VM_URL, data=body, method="POST")
            try:
                with urllib.request.urlopen(req, timeout=10):
                    pass
            except Exception as e:
                print(f"import failed: {e}", file=sys.stderr, flush=True)
                self._reply(502, "storage unavailable\n")
                return

            self._reply(200, "ok\n")


    def main():
        srv = ThreadingHTTPServer(LISTEN, Handler)
        print(f"listening on {LISTEN[0]}:{LISTEN[1]}", flush=True)
        srv.serve_forever()


    main()
  '';
in
{
  # LOCATION_PASSWORD=<random>       (basic auth password, user "phone")
  # HOME_LAT=<decimal degrees>       (optional, enables the home/away gauge)
  # HOME_LON=<decimal degrees>
  # HOME_RADIUS_METERS=200           (optional)
  age.secrets.location-env.file = ../../../../hosts/shimmers/secrets/location-env.age;

  systemd.services.location-ingest = {
    description = "GPSLogger to victoriametrics ingest";
    after = [
      "network-online.target"
      "victoriametrics.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${ingestServer}/bin/location-ingest";
      EnvironmentFile = [ config.age.secrets.location-env.path ];

      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = "5s";

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };

  services.nginx.virtualHosts.${domain} = mkProxyHost {
    port = 3083;
    websockets = false;
  };
}
