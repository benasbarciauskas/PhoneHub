# PhoneDrop — drag-to-phone Dock droplet (design)

Date: 2026-06-24
Status: approved-pending-review

## Goal

Drag a photo onto a Dock icon → it strips metadata and **auto-appears in the
Motorola's gallery**, over any network, with nothing for the user to tap on the
phone. Sender = the owner's own Mac, target = the owner's own Android phone.

## Why this shape (decisions already settled)

- **Tailscale ≠ same wifi.** Tailscale is a mesh VPN over the internet (NAT
  traversal + DERP relays). Phone on cellular + Mac on home wifi reach each other
  directly via the tailnet. No shared LAN required.
- Phone **is** on the tailnet → **no Tailscale Funnel** (public internet +
  password) and **no web download page with a manual tap**. Both were only needed
  for an off-tailnet, browser-only phone. Superseded.
- True "auto-download" to an Android phone is impossible from a browser tab
  (browser security needs a tap). It requires the Mac to *push* to the phone.
  The phone is on the tailnet and reachable, so the push channel is **adb over
  Tailscale** — works across any network, lands the file directly in the gallery,
  needs no custom APK, no sync app, no cloud.
- PhoneHub already speaks adb/scrcpy — this reuses that dependency.

## Architecture

```
[drag photo onto PhoneDrop.app Dock icon]
        │  (AppleScript droplet `on open` → shells to phonedrop.sh push <files>)
        ▼
phonedrop.sh  (all logic; testable; absolute tool paths)
  1. ensure adb connected to phone over Tailscale  (idempotent `adb connect`)
  2. for each dropped file:
       a. copy to temp           (never mutate the user's original)
       b. exiftool -all= on temp (strip EXIF/GPS)
       c. adb push temp → /sdcard/DCIM/PhoneDrop/
       d. media-scan that path   (so it shows in the gallery now)
  3. macOS notification: "Sent N photos to Motorola" / failure reason
```

### Components

| Unit | Responsibility | Depends on |
|------|----------------|------------|
| `PhoneDrop.app` (droplet) | Dock drop target. Thin AppleScript shim: `on open theFiles` → `phonedrop.sh push <quoted paths>`. No logic. | osacompile, phonedrop.sh |
| `scripts/phonedrop.sh` | All behavior. Verbs: `push <files…>`, `connect`, `status`, `install`, `config`. | adb, exiftool, tailscale, osascript |
| `~/.config/phonedrop/config` | `PHONE_HOST` (Tailscale MagicDNS name, e.g. `motorola`), `ADB_PORT` (default 5555), `DEST` (default `/sdcard/DCIM/PhoneDrop/`). | — |
| installer (`phonedrop.sh install`) | Compile droplet → `~/Applications/PhoneDrop.app` (local disk). Copy logic script → `~/Library/Application Support/PhoneDrop/`. Seed config. | — |

The repo holds **source** (droplet.applescript, phonedrop.sh, installer). The
**installed** copies live on local disk (`~/Applications`, `~/Library`) so they
survive the X10 Pro drive being unmounted, and so a Dock icon never points at a
pruned `.worktrees/` path.

### adb-over-Tailscale connection

- One-time on phone: enable Developer Options → **Wireless debugging**, pair with
  the Mac once, then `adb tcpip 5555` to pin a stable port.
- Mac resolves the phone by its Tailscale MagicDNS name (config `PHONE_HOST`);
  `adb connect $PHONE_HOST:$ADB_PORT` is run before every push (idempotent — a
  no-op if already connected).
- `// ponytail: reconnect-on-each-drop. Android may reset the wireless-debug port
  on reboot/idle; if `connect` fails the droplet notifies "re-pair Wireless
  Debugging" rather than silently dropping the photo. Persistent pairing only if
  this proves flaky.`

### PATH gotcha (load-bearing)

AppleScript `do shell script` runs with a minimal PATH
(`/usr/bin:/bin:/usr/sbin:/sbin`). adb (`/opt/homebrew/bin`), exiftool
(`/opt/homebrew/bin`), tailscale (`/usr/local/bin`) are NOT on it. phonedrop.sh
must reference tools by absolute path (resolved once at install, written to
config) or set PATH explicitly. Otherwise drops silently no-op.

## Metadata stripping

- `exiftool -all= -o <temp> <original>` (or copy-then-strip-in-place on the temp).
  Removes EXIF incl. GPS. Works on a **copy** — the dropped original is never
  modified.
- Non-image files (if ever dropped): skip strip, push as-is. (YAGNI: photos are
  the use case; just don't crash on a PDF.)

## Security / trust boundary

- Transport is the **private tailnet only** — not public. adb port is reachable
  solely by devices on the owner's tailnet; Tailscale ACLs gate it. Never exposed
  via Funnel/public.
- Input validation: dropped paths are quoted and passed as argv (no shell
  interpolation into a command string); `DEST` is a fixed config value, not user
  input; phone host validated against `tailscale status` before connect.
- No secrets involved (no password, no token) — the tailnet is the auth boundary.

## Testing

`scripts/phonedrop.sh check` (smoke test, the one runnable check):
- config present and tools resolve to executable absolute paths;
- `adb connect` to `$PHONE_HOST:$ADB_PORT` succeeds and `adb devices` lists it;
- a 1-px temp JPEG with injected GPS EXIF, after `exiftool -all=`, reports **no**
  GPS/EXIF tags (asserts the strip actually works);
- dry-run push path resolves (DEST writable via `adb shell test -w`).
Fails loudly (non-zero + notification) on any broken step.

Plus a tiny `tests/` shell check for the pure logic (arg quoting, config parse,
strip assertion on a fixture image) runnable without a phone attached.

## Out of scope (later / YAGNI)

- PhoneHub.app UI integration (this is Phase A — standalone droplet). A PhoneHub
  "File Drop" panel + live status is the follow-up.
- Phone → Mac direction, multi-file folders as zips, video transcoding,
  multi-device fan-out, a strip on/off toggle (ship strip-on per the decision).

## One-time setup (documented for the user)

1. Phone: install Tailscale, log into the tailnet.
2. Phone: Developer Options → Wireless debugging → pair with the Mac once.
3. Mac: `scripts/phonedrop.sh install`, then set `PHONE_HOST` in the config.
4. Drag PhoneDrop.app to the Dock. Drop photos onto it.
