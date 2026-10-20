#!/usr/bin/env bash
# Copyright (C) ConfigHub, Inc.
# SPDX-License-Identifier: MIT
#
# Bring confighub/argobot's main into k8sbot while argobot is still where the
# team develops. Delete this script, and the argobot-renamed branch, once
# k8sbot is authoritative.
#
# Two branches:
#   argobot-renamed  argobot's main with the mechanical rename applied
#                    (argobot -> k8sbot in every file, manifests moved to
#                    k8sbot.yaml). Each sync adds one commit whose parents are
#                    the previous argobot-renamed and argobot's main.
#   main             argobot-renamed plus the README's notes and this script,
#                    so its code is argobot's, renamed. Releases are tagged
#                    on main with argobot's version: k8sbot vN is argobot vN.
#
# A sync adds the next argobot-renamed commit and merges it into main. The
# merge base is the previous argobot-renamed commit, so the merge conflicts only
# where argobot changed the README's opening lines. The merge is left
# uncommitted for review.
#
# Usage: scripts/sync-from-argobot.sh            (from the k8sbot checkout, on main)
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "working tree is not clean" >&2
  exit 1
fi
if [[ "$(git symbolic-ref --short HEAD)" != main ]]; then
  echo "run this on main" >&2
  exit 1
fi

if ! git remote get-url argobot >/dev/null 2>&1; then
  git remote add argobot https://github.com/confighub/argobot.git
  git config remote.argobot.tagOpt --no-tags
fi
git fetch --no-tags argobot main
git fetch origin argobot-renamed:argobot-renamed
upstream=$(git rev-parse --short argobot/main)

if git merge-base --is-ancestor argobot/main argobot-renamed; then
  echo "argobot-renamed already has argobot/main ($upstream)"
else
  # Rename argobot/main in a scratch worktree and record the result as the next
  # argobot-renamed commit.
  tmp=$(mktemp -d)
  trap 'git worktree remove --force "$tmp" >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT
  git worktree add -q --detach "$tmp" argobot/main
  tree=$(
    cd "$tmp"
    for f in $(git ls-files '*argobot.yaml'); do
      git mv "$f" "$(dirname "$f")/k8sbot.yaml"
    done
    git grep -l -i argobot | while read -r f; do
      sed -i.bak -e 's/Argobot/K8sbot/g;s/ARGOBOT/K8SBOT/g;s/argobot/k8sbot/g' "$f"
      rm -f "$f.bak"
    done
    unformatted=$(gofmt -l .)
    [[ -z "$unformatted" ]] || gofmt -w $unformatted
    git add -A
    git write-tree
  )
  commit=$(git commit-tree "$tree" -p argobot-renamed -p argobot/main \
    -m "Rename argobot $upstream to k8sbot (mechanical)")
  git update-ref refs/heads/argobot-renamed "$commit"
fi

if git merge-base --is-ancestor argobot-renamed HEAD; then
  echo "main already has argobot-renamed"
  exit 0
fi

if ! git merge --no-ff --no-commit argobot-renamed; then
  echo
  echo "Conflicts where argobot changed lines k8sbot also changed; resolve them, then:"
  git diff --name-only --diff-filter=U | sed 's/^/  /'
  echo "  go vet ./... && go test ./... && git commit -m \"Sync from argobot $upstream\""
  echo "  git push origin main argobot-renamed"
  exit 1
fi

go vet ./...
go test ./...

echo
echo "Merged argobot/main ($upstream); not committed."
echo "Mentions of argobot left (expected: the README's notes, this script):"
git grep -n -i argobot || true
echo
echo "Then: git commit -m \"Sync from argobot $upstream\" && git push origin main argobot-renamed"
release=$(git ls-remote --tags argobot | awk -v c="$(git rev-parse argobot/main)" '$1 == c && $2 ~ /refs\/tags\/v/ { sub("refs/tags/", "", $2); print $2 }')
if [[ -n "$release" ]]; then
  echo "argobot/main is release $release; after pushing: git tag $release main && git push origin $release"
fi
