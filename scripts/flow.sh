#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HERE/.git-standard/common.sh" ]; then source "$HERE/.git-standard/common.sh"
elif [ -f "$HERE/lib/common.sh" ]; then source "$HERE/lib/common.sh"
else echo "common.sh not found next to flow.sh" >&2; exit 1; fi

cmd="${1:-}"; shift || true
root="$(repo_root)"; cd "$root"

case "$cmd" in
  feature)
    name="${1:?usage: flow.sh feature <name>}"
    slug="$(slugify "$name")"
    has_remote && ensure_account "$(repo_owner)" || true
    has_remote && git fetch origin --quiet || true
    base="$(base_branch)"
    wt="$root/.worktrees/$slug"
    [ -e "$wt" ] && { echo "Worktree already exists: $wt"; exit 1; }
    if has_remote; then git worktree add -b "feat/$slug" "$wt" "origin/$base"
    else git worktree add -b "feat/$slug" "$wt" "$base"; fi
    echo "✓ worktree $wt  (feat/$slug off $base)"
    echo "  Work there, commit, then run: scripts/flow.sh done"
    ;;
  done)
    branch="$(git branch --show-current)"
    case "$branch" in main|beta) echo "✋ On $branch — not a feature branch."; exit 1;; esac
    [ -n "$(git status --porcelain)" ] && { echo "✋ Commit your changes first:"; git status --short; exit 1; }
    ensure_account "$(repo_owner)"
    base="$(base_branch)"
    git push -u origin "$branch" --quiet
    if gh pr view "$branch" >/dev/null 2>&1; then
      echo "✅ PR already open: $(gh pr view "$branch" --json url -q .url)"
    else
      gh pr create --base "$base" --head "$branch" --fill
    fi
    ;;
  promote)
    ensure_account "$(repo_owner)"
    git ls-remote --exit-code --heads origin beta >/dev/null 2>&1 || { echo "No beta branch — nothing to promote."; exit 1; }
    if gh pr list --base main --head beta --state open --json number -q '.[0].number' | grep -q .; then
      echo "✅ Promotion PR already open."
    else
      gh pr create --base main --head beta --title "release: promote beta → main" --body "Promote tested beta to live."
    fi
    ;;
  sync)
    has_remote && git fetch --prune origin --quiet || true
    git worktree prune
    base="$(base_branch)"
    for b in $(git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null); do
      case "$b" in main|beta) continue;; esac
      git worktree list --porcelain | grep -q "branch refs/heads/$b" && continue
      if git merge-base --is-ancestor "$b" "origin/$base" 2>/dev/null; then
        git branch -D "$b" >/dev/null 2>&1 && echo "pruned merged branch $b"
      fi
    done
    echo "✓ synced"
    ;;
  *)
    echo "usage: flow.sh <feature|done|promote|sync> [args]"; exit 1;;
esac
