# Share to Community Design

## Goal

Let a PhoneHub user export an AI preset or recorded automation into the public
`benasbarciauskas/phonehub-presets` format and submit it as a GitHub pull
request without cloning the catalog or storing credentials.

## Export boundary

`PhoneHubCore` owns deterministic export and validation. A community document
contains `name`, `platform`, `app`, and `steps` in that order, uses stable
pretty-printed JSON, strips every internal UUID and coordinate, and rejects
empty top-level fields or steps. Point actions require a non-empty label and
report their zero-based step index. `switchDevice` is never shareable. All
other step values follow the catalog schema, including direction, URL, prompt,
and non-negative duration constraints.

AI presets map their goal to one `aiStep`. Slugs are lowercase ASCII
alphanumeric runs separated by one hyphen. The path is
`presets/<platform>/<app-slug>/<preset-slug>.json`.

## GitHub submission

`CommunityShareController` runs `gh` through PhoneHubCore's existing argv-only
process helper on a detached task and returns to the main actor. It verifies
authentication, resolves the current login, rejects an upstream-main path
collision, forks only for non-owner users, creates a branch from the target
repository's default-branch HEAD, uploads base64 JSON with the Contents API,
and opens a pull request against upstream `main`. Missing or unauthenticated
`gh` produces one actionable install/login message. The controller never uses
a shell string, local clone, token, or credential store.

## UI

Preset and automation rows gain `Share to Community…` in their context menus.
A reusable 360-point sheet starts with iOS selected, requires an explicit
platform selection plus non-empty app and preset names, and previews the mapped
step descriptions. It live-runs the core exporter so coordinate-only actions,
device switches, empty steps, and schema-invalid values appear inline before
submission. Submission shows progress; success keeps the sheet open with a
clickable pull-request URL and Done; errors remain inline with editable fields.

## Testing and delivery

Core tests are written and observed failing before export implementation. They
cover exact JSON/key order, ID/coordinate stripping, all supported mappings,
point-label errors, `switchDevice`, empty inputs and steps, schema value errors,
slug collapse/collisions, paths, and AI-goal mapping. The final gate runs the
full Swift test suite and required Swift build command, followed by an
adversarial diff review and commit-identity check.
