"""Two-way sync between navidrome's starred songs and Last.fm's loved tracks.

Runs for every navidrome user who linked Last.fm in the web UI; navidrome
keeps that session key in its database. Songs are matched by artist and
title (Last.fm knows nothing else), so a song counts as liked when any copy
of it in the library is starred.

The state file holds both sides as they were after the previous run, so a
like that disappeared on one side is an unlike there, and is passed on. A
like added on one side while it was removed on the other wins. Without a
state file (the first run) both sides are merged, nothing is removed.
"""

import hashlib
import json
import os
import sqlite3
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

NAVIDROME = "http://127.0.0.1:4533/rest"
NAVIDROME_DB = "file:/var/lib/navidrome/navidrome.db?mode=ro"
LASTFM = "https://ws.audioscrobbler.com/2.0/"
STATE_DIR = os.environ.get("STATE_DIRECTORY", "/var/lib/navidrome-lastfm-loves")
API_KEY = os.environ["ND_LASTFM_APIKEY"]
SECRET = os.environ["ND_LASTFM_SECRET"]
DRY_RUN = "--dry-run" in sys.argv


def log(user, msg):
    print(f"{user}: {msg}", flush=True)


def norm(text):
    text = unicodedata.normalize("NFKC", text or "").casefold()
    for a, b in (("\u2019", "'"), ("\u2018", "'"), ("\u201c", '"'), ("\u201d", '"')):
        text = text.replace(a, b)
    return " ".join(text.split())


def key(artist, title):
    return f"{norm(artist)}\t{norm(title)}"


def http(url, data=None, headers=None):
    body = urllib.parse.urlencode(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, headers=headers or {})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as err:
            if err.code < 500 and err.code != 429:
                try:
                    payload = json.load(err)
                except ValueError:
                    payload = err.reason
                raise RuntimeError(f"{url.split('?')[0]}: {payload}") from err
        except (urllib.error.URLError, TimeoutError):
            pass
        time.sleep(2 ** attempt)
    raise RuntimeError(f"{url.split('?')[0]}: giving up after retries")


def lastfm(method, sk=None, post=False, **params):
    params = {"method": method, "api_key": API_KEY, **params}
    if sk:
        params["sk"] = sk
        sig = "".join(k + params[k] for k in sorted(params)) + SECRET
        params["api_sig"] = hashlib.md5(sig.encode()).hexdigest()
    params["format"] = "json"
    if post:
        result = http(LASTFM, data=params)
        time.sleep(0.25)
    else:
        result = http(LASTFM + "?" + urllib.parse.urlencode(params))
    if "error" in result:
        raise RuntimeError(f"last.fm {method}: {result.get('message')}")
    return result


def navidrome(user, endpoint, **params):
    params = {"v": "1.16.1", "c": "lastfm-loves", "f": "json", **params}
    url = f"{NAVIDROME}/{endpoint}?" + urllib.parse.urlencode(params, doseq=True)
    result = http(url, headers={"Remote-User": user})["subsonic-response"]
    if result["status"] != "ok":
        raise RuntimeError(f"navidrome {endpoint}: {result.get('error')}")
    return result


def library(user):
    songs, offset = [], 0
    while True:
        page = navidrome(user, "search3", query="", songCount=500, songOffset=offset,
                         artistCount=0, albumCount=0)
        batch = page.get("searchResult3", {}).get("song", [])
        songs += batch
        if len(batch) < 500:
            return songs
        offset += 500


def song_artists(song):
    names = [a["name"] for a in song.get("artists") or []]
    return names or [song.get("artist", "")]


def loved_tracks(name):
    tracks, page = [], 1
    while True:
        result = lastfm("user.getLovedTracks", user=name, limit="1000", page=str(page))
        loved = result["lovedtracks"]
        batch = loved.get("track", [])
        # A page with a single track comes as an object, not a list.
        tracks += [batch] if isinstance(batch, dict) else batch
        if page >= int(loved["@attr"]["totalPages"]):
            return tracks
        page += 1


def sync(user, sk):
    name = lastfm("user.getInfo", sk=sk)["user"]["name"]

    # Every song by its canonical key (first artist and title), and every
    # spelling Last.fm might use for it (any of its artists) to that key.
    songs = library(user)
    by_key, aliases = {}, {}
    for song in songs:
        artists = song_artists(song)
        canonical = key(artists[0], song["title"])
        by_key.setdefault(canonical, []).append(song)
        for artist in artists + [song.get("artist", "")]:
            aliases.setdefault(key(artist, song["title"]), canonical)

    starred = {key(song_artists(s)[0], s["title"]) for s in songs if s.get("starred")}
    loved, loved_as = set(), {}
    for track in loved_tracks(name):
        canonical = aliases.get(key(track["artist"]["name"], track["name"]))
        if canonical:
            loved.add(canonical)
            loved_as.setdefault(canonical, []).append((track["artist"]["name"], track["name"]))

    path = os.path.join(STATE_DIR, f"{user}.json")
    try:
        with open(path) as f:
            state = json.load(f)
    except FileNotFoundError:
        state = None
    prev_starred = set(state["navidrome"]) if state else starred
    prev_loved = set(state["lastfm"]) if state else loved
    # Loved by an earlier run, but not seen on Last.fm yet (it may have
    # corrected the spelling); not having it there is no unlike.
    unconfirmed = set(state.get("unconfirmed", [])) - loved if state else set()

    unstarred = prev_starred - starred
    unloved = prev_loved - loved - unconfirmed
    added_starred = starred - prev_starred
    added_loved = loved - prev_loved

    # A sudden wipe of one side is more likely a hiccup than intent.
    for side, before, gone in (("navidrome", prev_starred, unstarred), ("last.fm", prev_loved, unloved)):
        if len(gone) > 10 and len(gone) > len(before) / 2:
            raise RuntimeError(f"{len(gone)} of {len(before)} likes vanished on {side}, not syncing")

    to_unlove = {k for k in unstarred & loved if k not in added_loved}
    to_unstar = {k for k in unloved & starred if k not in added_starred}
    to_love = starred - loved - to_unstar
    to_star = loved - starred - to_unlove

    for k in sorted(to_love):
        song = by_key[k][0]
        log(user, f"love on last.fm: {song_artists(song)[0]} - {song['title']}")
        if not DRY_RUN:
            lastfm("track.love", sk=sk, post=True, artist=song_artists(song)[0], track=song["title"])
    for k in sorted(to_unlove):
        for artist, title in loved_as[k]:
            log(user, f"unlove on last.fm: {artist} - {title}")
            if not DRY_RUN:
                lastfm("track.unlove", sk=sk, post=True, artist=artist, track=title)
    for k in sorted(to_star):
        song = by_key[k][0]
        log(user, f"star in navidrome: {song_artists(song)[0]} - {song['title']}")
        if not DRY_RUN:
            navidrome(user, "star", id=song["id"])
    for k in sorted(to_unstar):
        for song in by_key[k]:
            if song.get("starred"):
                log(user, f"unstar in navidrome: {song_artists(song)[0]} - {song['title']}")
                if not DRY_RUN:
                    navidrome(user, "unstar", id=song["id"])

    if DRY_RUN:
        return
    final_starred = (starred | to_star) - to_unstar
    state = {
        "navidrome": sorted(final_starred),
        "lastfm": sorted((loved | to_love) - to_unlove),
        "unconfirmed": sorted(((unconfirmed | to_love) - loved) & final_starred),
    }
    with open(path + ".tmp", "w") as f:
        json.dump(state, f, indent=1)
    os.replace(path + ".tmp", path)


def main():
    db = sqlite3.connect(NAVIDROME_DB, uri=True)
    users = db.execute(
        "SELECT u.user_name, p.value FROM user_props p JOIN user u ON u.id = p.user_id"
        " WHERE p.key = 'LastFMSessionKey' AND p.value != ''"
    ).fetchall()
    db.close()
    failed = False
    for user, sk in users:
        try:
            sync(user, sk)
        except Exception as err:
            log(user, f"sync failed: {err}")
            failed = True
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
