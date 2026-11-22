#!/usr/bin/env python3
"""Katzentempel forwarding proxy with L'osteria-style loyalty response rewrites."""

import ipaddress
import json
import logging
import os
import random
import uuid
from http.cookies import SimpleCookie
from urllib.parse import urlsplit, urlunsplit

import requests
from flask import Flask, Response, jsonify, request, stream_with_context
from werkzeug.middleware.proxy_fix import ProxyFix
from datetime import datetime, timedelta, time

CLIENT_ID = "22310692-261b-4653-9c01-c2bc11459049"
API_PREFIX = f"/api/v1/clients/{CLIENT_ID}"
EDITOR_PREFIX = f"/api/v1/app_editor/configuration_update/{CLIENT_ID}"
# Authentication is global; the client ID is supplied in the request payload.
USERS_PREFIX = "/api/v1/users"
RELATIONSHIP_PREFIX = f"/api/v1/customer-relationships/client/{CLIENT_ID}"
SCOPED_PREFIXES = (
    ("/api/v1/clients", API_PREFIX),
    ("/api/v1/app_editor/configuration_update", EDITOR_PREFIX),
    ("/api/v1/customer-relationships/client", RELATIONSHIP_PREFIX),
)
HOP_HEADERS = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailer", "trailers", "transfer-encoding", "upgrade",
}


def origin(value):
    parts = urlsplit(value)
    if (parts.scheme not in {"http", "https"} or not parts.hostname
            or parts.username or parts.password or parts.path not in {"", "/"}
            or parts.query or parts.fragment or any(ord(c) < 33 for c in value)):
        raise ValueError("Expected an HTTP(S) origin without a path or credentials")
    parts.port  # Validate the port.
    return urlunsplit((parts.scheme, parts.netloc, "", "", ""))


def filtered_headers(headers):
    nominated = {s.strip().lower() for s in headers.get("Connection", "").split(",")}
    return [(key, value) for key, value in headers.items()
            if key.lower() not in HOP_HEADERS | nominated]


def is_loopback(host):
    if host == "localhost":
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def allowed_api_path(path):
    """Forward global API resources, but keep client-addressed resources scoped."""
    if not path.startswith("/api/v1/"):
        return False
    for collection, allowed in SCOPED_PREFIXES:
        if path == collection or path.startswith(collection + "/"):
            return path == allowed or path.startswith(allowed + "/")
    return True


# ── L'osteria-style session state ──────────────────────────────────────────

BOUNTY_PRICES: dict = {}


def get_bounty_price(bounty_id):
    return BOUNTY_PRICES.get(bounty_id, 0)


def set_bounty_price(bounty_id, price):
    BOUNTY_PRICES[bounty_id] = price


SESSION_POINTS: dict = {}


def get_points_for_session(session_id):
    return SESSION_POINTS.get(session_id, 690)


def set_points_for_session(session_id, points):
    SESSION_POINTS[session_id] = points


SESSION_ACTIVITY: dict = {}


def get_activity_for_session(session_id):
    return SESSION_ACTIVITY.get(session_id, [])


def set_activity_for_session(session_id, activity):
    SESSION_ACTIVITY[session_id] = activity


def generate_activity(days_range=500):
    """Generate one activity entry with timestamp, value, uuid, message, activity_class."""
    now = datetime.now()
    earliest = now - timedelta(days=days_range)
    while True:
        total_seconds = int((now - timedelta(minutes=1) - earliest).total_seconds())
        if total_seconds <= 0:
            break
        offset = random.randint(0, total_seconds)
        ts = earliest + timedelta(seconds=offset)
        if ts.weekday() <= 5 and time(13, 0) <= ts.time() <= time(22, 0):
            break
    timestamp_str = ts.strftime("%d.%m.%Y %H:%M:%S")
    value = random.choice(range(50, 201, 10))
    uid = str(uuid.uuid4())
    return {
        "timestamp": timestamp_str,
        "value": value,
        "uuid": uid,
    }


def rewrite_bounties_list(data, session_id):
    """Mark every in_shop entry as redeemable; set cr_points from session state."""
    if not isinstance(data, dict):
        return None
    for entry in data.get("in_shop", []):
        entry["is_redeemable"] = True
        entry["is_activateable"] = True
        entry["cr_points"] = get_points_for_session(session_id)
        set_bounty_price(entry["id"], entry.get("needed_points", 0))
    return json.dumps(data).encode("utf-8")


def rewrite_bounties(data, session_id):
    """Fill progress-bar fields on each bounty so the bar shows full."""
    if not isinstance(data, list):
        return None
    pts = get_points_for_session(session_id)
    for bounty in data:
        if not isinstance(bounty, dict):
            continue
        bounty["is_redeemable"] = True
        bounty["is_activateable"] = True
        if bounty.get("show_progress_bar"):
            bounty["cr_points"] = pts
            bounty["cr_rank"] = 0
            bounty["needed_visits"] = 0
            bounty["redeem_count"] = 0
            if bounty.get("ranks") is None:
                bounty["ranks"] = 1
    return json.dumps(data).encode("utf-8")


def rewrite_activity_feed(data, session_id):
    """Replace activity results with 75 generated activities sorted by timestamp desc."""
    if not isinstance(data, dict) or "results" not in data:
        return None
    activity = data["results"][-1] if data["results"] else None
    data["results"].clear()
    stored = get_activity_for_session(session_id)
    if stored:
        data["results"].extend(stored)
    else:
        for _ in range(75):
            rand = generate_activity(500)
            new_activity = (activity.copy() if activity else {})
            new_activity["created"] = rand["timestamp"]
            new_activity["points"] = rand["value"]
            new_activity["uuid"] = rand["uuid"]
            if rand["value"] in [50, 75, 100, 200]:
                new_activity["message"] = "Code redeemed"
                new_activity["activity_class"] = 1
            else:
                new_activity["message"] = "Purchase"
                new_activity["activity_class"] = 0
            data["results"].append(new_activity)
        data["results"].sort(
            key=lambda x: datetime.strptime(x["created"], "%d.%m.%Y %H:%M:%S"),
            reverse=True,
        )
        set_activity_for_session(session_id, data["results"])
    return json.dumps(data).encode("utf-8")


def rewrite_redeem(data, request_data, session_id):
    """Force success to true; deduct points and add activity entry."""
    if not isinstance(data, dict):
        return None
    data["success"] = True
    try:
        body = json.loads(request_data) if request_data else {}
    except Exception:
        body = {}
    bounty_id = body.get("bounty_id")
    if bounty_id:
        cost = get_bounty_price(bounty_id)
        current = get_points_for_session(session_id)
        set_points_for_session(session_id, current - cost)
        activity = get_activity_for_session(session_id)
        now_str = datetime.now().strftime("%d.%m.%Y %H:%M:%S")
        new_entry = (activity[0].copy() if activity else {})
        new_entry["created"] = now_str
        new_entry["points"] = cost
        new_entry["uuid"] = str(uuid.uuid4())
        new_entry["message"] = "Code redeemed"
        new_entry["activity_class"] = 1
        activity.insert(0, new_entry)
        set_activity_for_session(session_id, activity)
    return json.dumps(data).encode("utf-8")


def rewrite_customer_relationships(data, session_id):
    """Set loyalty points to session state value."""
    if not isinstance(data, dict):
        return None
    points = get_points_for_session(session_id)
    data["points"] = points
    data["cr_points"] = points
    return json.dumps(data).encode("utf-8")


def rebase_cookie(value, upstream_host, local_host):
    """Keep sessions usable at the proxy without weakening remote HTTPS cookies."""
    cookie = SimpleCookie()
    try:
        cookie.load(value)
    except Exception:
        return value
    if not cookie:
        return value
    for morsel in cookie.values():
        domain = morsel["domain"].lstrip(".").lower()
        if domain and (domain == upstream_host or upstream_host.endswith("." + domain)):
            morsel["domain"] = ""  # Host-only cookie at the proxy.
        if is_loopback(local_host):
            morsel["secure"] = ""
    return cookie.output(header="").strip()


def create_app(upstream=None, trust_proxy=None):
    upstream = origin(upstream or os.environ.get("ORIGINAL_HOST", "https://api.helloagain.at"))
    app = Flask(__name__)
    if trust_proxy is None:
        trust_proxy = os.environ.get("TRUST_PROXY", "0") == "1"
    if trust_proxy:
        # Enable only behind a trusted, loopback-bound reverse proxy.
        app.wsgi_app = ProxyFix(app.wsgi_app, x_for=0, x_proto=1, x_host=0, x_port=0, x_prefix=0)
    app.config["MAX_CONTENT_LENGTH"] = 32 * 1024 * 1024
    app.url_map.merge_slashes = False

    @app.get("/healthz")
    def health():
        return jsonify(status="ok", upstream=upstream, client_id=CLIENT_ID)

    @app.route("/", defaults={"path": ""}, methods=["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"])
    @app.route("/<path:path>", methods=["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"])
    def forward(path):
        if not allowed_api_path(request.path):
            return jsonify(error="This proxy only serves the Katzentempel client API"), 404

        # Extract session ID from cookies for rewrite state.
        session_id = None
        if "Cookie" in request.headers:
            cookies = SimpleCookie()
            cookies.load(request.headers["Cookie"])
            session_id = cookies.get("sessionid")
            if session_id:
                session_id = session_id.value

        # Ensure session has points.
        if session_id and get_points_for_session(session_id) < 300:
            set_points_for_session(session_id, 690)

        # RAW_URI retains percent-encoding and the original query order.
        raw_uri = request.environ.get("RAW_URI") or request.full_path.rstrip("?")
        parts = urlsplit(raw_uri)
        target = upstream + (parts.path or "/")
        if parts.query:
            target += "?" + parts.query
        headers = {k: v for k, v in filtered_headers(request.headers)
                   if k.lower() not in {"host", "content-length"}
                   and not k.lower().startswith("x-forwarded-")}

        # Capture request body for redeem rewrite.
        request_data = request.get_data()

        try:
            # No shared Session: requests must never retain another user's cookies.
            result = requests.request(
                request.method, target, headers=headers, data=request_data,
                allow_redirects=False, stream=True, timeout=(10, 30),
            )
        except requests.Timeout:
            return jsonify(error="Upstream timed out"), 504
        except requests.RequestException:
            app.logger.warning("Upstream request failed", exc_info=False)
            return jsonify(error="Upstream unavailable"), 502

        outgoing = [(k, v) for k, v in filtered_headers(result.headers)
                    if k.lower() not in {"set-cookie", "content-encoding"}]
        upstream_host = urlsplit(upstream).hostname
        local_host = urlsplit(request.host_url).hostname
        for value in result.raw.headers.getlist("Set-Cookie"):
            outgoing.append(("Set-Cookie", rebase_cookie(value, upstream_host, local_host)))
        outgoing = [(k, request.host_url.rstrip("/") + v[len(upstream):]
                     if k.lower() == "location" and (v == upstream or v.startswith(upstream + "/"))
                     else v) for k, v in outgoing]

        # Read upstream body once; decompress so we can rewrite JSON.
        is_gzip = "content-encoding" in result.headers and "gzip" in result.headers.get("content-encoding", "").lower()

        if is_gzip:
            content = result.content  # requests auto-decompresses .content
            result.close()
            # Try to rewrite decompressed content.
            rewritten = None
            try:
                data = json.loads(content)
            except Exception:
                data = None
            if data is not None:
                if "bounties-list" in request.path:
                    rewritten = rewrite_bounties_list(data, session_id)
                elif "bounties/" in request.path and "bounties-list" not in request.path:
                    rewritten = rewrite_bounties(data, session_id)
                elif "activity-feed" in request.path:
                    rewritten = rewrite_activity_feed(data, session_id)
                elif "redeem" in request.path:
                    rewritten = rewrite_redeem(data, request_data, session_id)
                elif "customer-relationships/client/" in request.path:
                    rewritten = rewrite_customer_relationships(data, session_id)
            if rewritten is not None:
                import gzip as _gzip
                compressed = _gzip.compress(rewritten)
                outgoing.append(("Content-Encoding", "gzip"))
                outgoing.append(("Content-Length", str(len(compressed))))
                return Response(compressed, status=result.status_code, headers=outgoing)
            # No rewrite: gzip-compress the original content and return.
            import gzip as _gzip
            compressed = _gzip.compress(content)
            outgoing.append(("Content-Encoding", "gzip"))
            outgoing = [(k, v) for k, v in outgoing if k.lower() != "content-length"]
            outgoing.append(("Content-Length", str(len(compressed))))
            return Response(compressed, status=result.status_code, headers=outgoing)

        content = result.content
        result.close()

        # Apply L'osteria-style response rewrites.
        rewritten = None
        try:
            data = json.loads(content)
        except Exception:
            data = None

        if data is not None:
            if "bounties-list" in request.path:
                rewritten = rewrite_bounties_list(data, session_id)
            elif "bounties/" in request.path and "bounties-list" not in request.path:
                rewritten = rewrite_bounties(data, session_id)
            elif "activity-feed" in request.path:
                rewritten = rewrite_activity_feed(data, session_id)
            elif "redeem" in request.path:
                rewritten = rewrite_redeem(data, request_data, session_id)
            elif "customer-relationships/client/" in request.path:
                rewritten = rewrite_customer_relationships(data, session_id)

        if rewritten is not None:
            outgoing = [(k, v) for k, v in outgoing if k.lower() != "content-length"]
            outgoing.append(("Content-Length", str(len(rewritten))))
            return Response(rewritten, status=result.status_code, headers=outgoing)

        # Non-rewritten, non-gzip: return decompressed content directly.
        outgoing = [(k, v) for k, v in outgoing if k.lower() != "content-length"]
        outgoing.append(("Content-Length", str(len(content))))
        return Response(content, status=result.status_code, headers=outgoing)

    return app


app = create_app()

if __name__ == "__main__":
    # Werkzeug's default access log includes sensitive query strings.
    logging.getLogger("werkzeug").setLevel(logging.ERROR)
    app.run(host=os.environ.get("LISTEN_HOST", "127.0.0.1"),
            port=int(os.environ.get("LISTEN_PORT", "3083")), debug=False, threaded=True)
