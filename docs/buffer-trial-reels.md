# Buffer → Instagram trial reels (PhoneHub preset)

Posts trial reels natively on the phone using captions and slot times from a
Buffer channel's queue. One preset does both jobs: run it manually to post
immediately, or let PhoneHub's daily schedules fire it at your Buffer slot
times — the reel goes live exactly when Buffer would have posted it, no
in-app Instagram scheduling (date-picker automation is brittle and IG's
scheduler needs no involvement when PhoneHub is the scheduler).

## One-time setup

1. **Buffer token** (from the Buffer account that owns the channel — log in
   there, publish.buffer.com/settings/api → Create Access Token), then in a
   real terminal:

   ```sh
   ~/rotate-keychain-secret.sh buffer-token "$USER"
   ```

2. **Smoke test** — lists channels + their posting schedules:

   ```sh
   python3 scripts/buffer_next_captions.py --check
   ```

   Note the channel handle and the schedule times — the times become your
   PhoneHub daily schedules below.

3. **Buffer channel must be reminder-mode** (notification-only). If Buffer
   auto-publishes the queue, you'll double-post.

4. Instagram account must be a professional account (trial reels
   requirement), logged in on the phone, reels downloaded to the camera roll.

## Text source

In PhoneHub → Text Sources, create `reel-captions`:

- Mode: cycle (cursor is reset by the refresh anyway)
- Refresh command:

  ```sh
  python3 "/path/to/PhoneHub/scripts/buffer_next_captions.py" --channel <handle>
  ```

The refresh runs before every automation run and replaces the items with the
current pending queue, oldest due first — the caption step always types the
next unposted caption. If the command fails, the run fails (never posts a
stale caption).

## The preset

Build in Builder (or record one manual run with human recording, then trim).
Coordinates come from your device via the tap picker:

1. `launchApp` Instagram
2. tap ➕ (create) → tap **Reel**
3. tap first gallery tile (newest video)
4. tap **Next** → `wait` → **Next**
5. tap caption field → `typeText` bound to `reel-captions`
6. `scrollTo "Trial"` → tap the **Share as trial reel** toggle
7. tap **Share** → `wait` → `pressHome`

On-success command (in the automation's edit sheet):

```sh
python3 "/path/to/PhoneHub/scripts/buffer_mark_posted.py" --channel <handle>
```

Removes the just-posted item from Buffer's queue so it can't double-remind
and the next run serves the next caption. Runs only when every step
succeeded.

## Schedules

Create 3 daily PhoneHub schedules targeting the preset + your iPhone, at the
channel's Buffer slot times (from `--check`). That's the "3 per day,
scheduled" automation. "Post one now" = run the same preset manually.

## Reel ↔ caption mapping

The preset taps the newest camera-roll video; the caption source serves the
oldest pending Buffer post. Download reels one at a time before each slot, or
in reverse queue order, so newest-in-roll = next-in-queue. If this bites,
the upgrade is an `aiStep` that picks the gallery tile matching the post.

## Gotchas

- Emoji-heavy captions: `typeText` goes through the mirroring keyboard —
  test one real caption first. If emoji drop, the fallback is a
  clipboard-paste step (Universal Clipboard).
- Runs require the iPhone Mirroring window to be visible (the command gate
  enforces this) and the Mac awake at slot times.
- The legacy Buffer REST endpoints (`api.bufferapp.com/1`) are what personal
  access tokens are documented against; if they 401/410, the fallback is
  Buffer's GraphQL (`graph.buffer.com`) with the same token — adjust the two
  scripts, interfaces stay the same.
