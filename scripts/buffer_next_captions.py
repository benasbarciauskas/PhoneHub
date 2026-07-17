#!/usr/bin/env python3
"""Print pending (scheduled, unsent) Buffer post captions for one channel.

Output: JSON array of caption strings, oldest due first — the exact format
PhoneHub's command-backed text sources consume (item 0 = next post).

Auth: BUFFER_TOKEN env var, else macOS keychain item `buffer-token`.
Mint the token at publish.buffer.com/settings/api while logged into the
Buffer account that owns the channel, then store it:
    ~/rotate-keychain-secret.sh buffer-token "$USER"

Usage:
    buffer_next_captions.py --channel <handle>      # captions JSON array
    buffer_next_captions.py --check                 # list channels + posting schedules
    buffer_next_captions.py --channel <handle> --times   # pending posts' due times
"""

import argparse
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request

BASE = "https://api.bufferapp.com/1"
TIMEOUT = 20


def token() -> str:
    tok = os.environ.get("BUFFER_TOKEN")
    if not tok:
        try:
            tok = subprocess.run(
                ["security", "find-generic-password", "-s", "buffer-token", "-w"],
                capture_output=True, text=True, timeout=10, check=True,
            ).stdout.strip()
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            tok = ""
    if not tok:
        sys.exit("No Buffer token: set BUFFER_TOKEN or keychain item 'buffer-token'.")
    return tok


def get(path: str, tok: str):
    url = f"{BASE}/{path}{'&' if '?' in path else '?'}access_token={urllib.parse.quote(tok)}"
    req = urllib.request.Request(url, headers={"User-Agent": "phonehub-buffer-sync"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.load(resp)


def find_profile(profiles: list, handle: str) -> dict:
    needle = handle.lstrip("@").lower()
    for p in profiles:
        names = {
            str(p.get("service_username", "")).lower(),
            str(p.get("formatted_username", "")).lstrip("@").lower(),
        }
        if needle in names or p.get("id") == handle:
            return p
    sys.exit(f"Channel '{handle}' not found. Run --check to list channels.")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--channel", help="channel handle / username / profile id")
    ap.add_argument("--check", action="store_true", help="list channels + schedules")
    ap.add_argument("--times", action="store_true", help="print due times, not captions")
    args = ap.parse_args()

    tok = token()
    profiles = get("profiles.json", tok)

    if args.check:
        for p in profiles:
            print(f"{p.get('service')} @{p.get('service_username')} id={p.get('id')} "
                  f"schedules={json.dumps(p.get('schedules', []))}")
        return

    if not args.channel:
        ap.error("--channel required (or use --check)")

    profile = find_profile(profiles, args.channel)
    pending = get(f"profiles/{profile['id']}/updates/pending.json", tok)
    updates = sorted(pending.get("updates", []), key=lambda u: u.get("due_at", 0))

    if args.times:
        for u in updates:
            print(u.get("due_time", u.get("due_at")))
        return

    print(json.dumps([u.get("text", "") for u in updates], ensure_ascii=False))


if __name__ == "__main__":
    main()
