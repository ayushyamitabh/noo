#!/usr/bin/env bash
# Imports open GitHub pull requests into Gitea as Agit PRs (refs/for/main).
# Gitea is the source of truth: review and merge there, and the push mirror
# updates GitHub. Run from cron, e.g. every 5 minutes:
#   */5 * * * * /srv/noo-sync/scripts/sync-github-prs.sh >> /var/log/noo-sync.log 2>&1
#
# One PR:  sync-github-prs.sh 42
# All:     sync-github-prs.sh
#
# Needs: git, curl, jq, and a clone whose `origin` is Gitea (SSH deploy key
# or token with write access) plus env var GITHUB_REPO (e.g. ayushyamitabh/noo).
# GITHUB_TOKEN is optional (read-only, public repo) but avoids rate limits.
set -euo pipefail

: "${GITHUB_REPO:?set GITHUB_REPO, e.g. ayushyamitabh/noo}"
STATE_DIR="${STATE_DIR:-$HOME/.noo-sync}"
BASE_BRANCH="${BASE_BRANCH:-main}"
mkdir -p "$STATE_DIR"

auth=()
[ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")

git remote get-url github >/dev/null 2>&1 ||
  git remote add github "https://github.com/$GITHUB_REPO.git"

import_pr() {
  local n="$1" pr head_sha title url
  pr=$(curl -fsS "${auth[@]}" "https://api.github.com/repos/$GITHUB_REPO/pulls/$n")
  head_sha=$(jq -r .head.sha <<<"$pr")
  title=$(jq -r '.title | gsub("[\r\n\t]+"; " ")' <<<"$pr")
  url=$(jq -r .html_url <<<"$pr")
  local stamp="$STATE_DIR/pr-$n"
  if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$head_sha" ]; then return; fi

  git fetch --quiet origin "$BASE_BRANCH"
  git fetch --quiet github "+refs/pull/$n/head"
  # Agit: pushing to refs/for/<base> with a stable topic opens a Gitea PR the
  # first time and updates the same PR on later pushes.
  git push origin "FETCH_HEAD:refs/for/$BASE_BRANCH" \
    -o "topic=gh-pr-$n" \
    -o "title=[GitHub #$n] $title" \
    -o "description=Imported from $url. Discuss on GitHub; merge here."
  echo "$head_sha" >"$stamp"
  echo "imported PR #$n @ $head_sha"
}

if [ "$#" -gt 0 ]; then
  for n in "$@"; do import_pr "$n"; done
else
  curl -fsS "${auth[@]}" \
    "https://api.github.com/repos/$GITHUB_REPO/pulls?state=open&per_page=50" |
    jq -r '.[].number' | while read -r n; do import_pr "$n"; done
fi
