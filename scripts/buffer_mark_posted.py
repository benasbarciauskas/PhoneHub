#!/usr/bin/env python3
"""Remove the oldest pending Buffer post for a channel (it was just posted natively).

Intended as a PhoneHub automation on-success hook: after the trial reel is
shared on the phone, drop the corresponding Buffer post so it can't
double-post or keep sending reminders, and so buffer_next_captions.py
serves the next caption on the following run.

Deletes via the updates/<id>/destroy endpoint (legacy API has no
"mark reminder as shared"). Buffer-side analytics for that post are lost;
the post itself is live on Instagram.

Auth: same as buffer_next_captions.py (BUFFER_TOKEN env or keychain
'buffer-token').

Usage:
    buffer_mark_posted.py --channel <handle>            # delete oldest pending
    buffer_mark_posted.py --channel <handle> --dry-run  # show what would go
"""

import argparse
import json
import sys
import urllib.parse
import urllib.request

from buffer_next_captions import BASE, TIMEOUT, find_profile, get, token


def post(path: str, tok: str):
    url = f"{BASE}/{path}"
    data = urllib.parse.urlencode({"access_token": tok}).encode()
    req = urllib.request.Request(url, data=data,
                                 headers={"User-Agent": "phonehub-buffer-sync"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.load(resp)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--channel", required=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    tok = token()
    profile = find_profile(get("profiles.json", tok), args.channel)
    pending = get(f"profiles/{profile['id']}/updates/pending.json", tok)
    updates = sorted(pending.get("updates", []), key=lambda u: u.get("due_at", 0))
    if not updates:
        sys.exit("No pending posts — nothing to remove.")

    oldest = updates[0]
    preview = (oldest.get("text") or "")[:80].replace("\n", " ")
    if args.dry_run:
        print(f"Would remove update {oldest['id']}: {preview}")
        return

    result = post(f"updates/{oldest['id']}/destroy.json", tok)
    if not result.get("success"):
        sys.exit(f"Destroy failed: {result}")
    print(f"Removed Buffer post {oldest['id']}: {preview}")


if __name__ == "__main__":
    main()
