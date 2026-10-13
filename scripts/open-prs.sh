#!/usr/bin/env bash
# Publish the reviewed local branch stack using an authenticated GitHub CLI.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
repository=huynhcntt2012/codexserver
if [[ "$(git remote get-url origin)" != "https://github.com/${repository}.git" ]]; then
  echo "Unexpected origin; review the repository URL before publishing." >&2
  exit 1
fi
gh auth status --hostname github.com
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or preserve pending changes before publishing." >&2
  exit 1
fi
branches=(main suni/01-arena suni/02-api suni/03-client suni/04-delivery)
for branch in "${branches[@]}"; do
  git show-ref --verify --quiet "refs/heads/$branch"
done
# Atomic push: no force, and no partial publication on a rejected ref.
git push --atomic origin "${branches[@]}"
titles=(
  "Add authoritative arena gameplay and multiplayer tests"
  "Add account API with persistent inventory and VIP status"
  "Add original Godot multiplayer client"
  "Add Docker deployment, CI and release runbooks"
)
bodies=(01-arena 02-api 03-client 04-delivery)
for index in 0 1 2 3; do
  head="${branches[index + 1]}"
  base="${branches[index]}"
  existing="$(gh pr list --repo "$repository" --head "$head" --state open --json url --jq '.[0].url // empty')"
  if [[ -n "$existing" ]]; then
    echo "$existing"
  else
    gh pr create --repo "$repository" --draft --base "$base" --head "$head" \
      --title "${titles[index]}" --body-file "docs/prs/${bodies[index]}.md"
  fi
done
