#!/usr/bin/env bash
# Shared helpers for the Ruflo Git Standard tooling. Source me; do not execute.

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' \
    | tr -cd '[:alnum:]-' | sed -E 's/-+/-/g; s/^-//; s/-$//'
}

repo_root() { git rev-parse --show-toplevel; }

has_remote() { git remote get-url origin >/dev/null 2>&1; }

# Pure URL→owner/repo parser. Handles every github remote form:
#   https://github.com/O/R.git, https://USER@github.com/O/R.git,
#   git@github.com:O/R.git, ssh://git@github.com/O/R.git
_parse_nwo() {
  local url="${1%.git}"
  url="${url#*://}"            # strip scheme:// (no-op if absent)
  url="${url#*@}"             # strip userinfo user@ (no-op if absent)
  url="${url#github.com[:/]}" # strip host (':' for scp form, '/' otherwise)
  printf '%s' "$url"
}

_parse_owner() { local nwo; nwo="$(_parse_nwo "$1")"; printf '%s' "${nwo%%/*}"; }

repo_owner() {
  has_remote || { printf ''; return 0; }
  _parse_owner "$(git remote get-url origin)"
}

repo_nwo() {
  _parse_nwo "${1:-$(git remote get-url origin 2>/dev/null)}"
}

# Switch the active gh account to the repo owner if needed.
ensure_account() {
  local owner="$1"; [ -z "$owner" ] && return 0
  local cur; cur="$(gh api user -q .login 2>/dev/null || true)"
  [ "$cur" = "$owner" ] && return 0
  gh auth switch --user "$owner" >/dev/null 2>&1 || {
    echo "⚠️  Could not switch gh account to '$owner'. Run: gh auth login --user $owner" >&2
    return 1
  }
}

# beta if it exists locally or on origin, else main.
base_branch() {
  if git show-ref --verify --quiet refs/heads/beta \
     || git ls-remote --exit-code --heads origin beta >/dev/null 2>&1; then
    printf 'beta'
  else
    printf 'main'
  fi
}

detect_type() {
  local root; root="$(repo_root)"
  if [ -f "$root/package.json" ] || [ -f "$root/web/package.json" ]; then echo web
  elif ls "$root"/*.xcodeproj "$root"/*.xcworkspace >/dev/null 2>&1 || [ -f "$root/Package.swift" ]; then echo ios
  elif [ -f "$root/.clasp.json" ] || [ -f "$root/appsscript.json" ]; then echo apps-script
  else echo blank; fi
}
