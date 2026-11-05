#!/usr/bin/env bash
# Publish only the reviewed Git commit, never local cache or secret files.
set -euo pipefail
cd "$(dirname "$0")/.."
GH=${GH:-gh}
command -v "$GH" >/dev/null || { echo "Install GitHub CLI or set GH to its path" >&2; exit 1; }
repo=estebanvizca/linux-sre-observability-kit
"$GH" auth status
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Create and review a local commit before publishing" >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Commit reviewed changes before publishing" >&2
  exit 1
fi
if "$GH" repo view "$repo" --json name >/dev/null 2>&1; then
  if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "https://github.com/$repo.git"
  fi
else
  "$GH" repo create "$repo" --public --source . --remote origin
fi
"$GH" auth setup-git
git push -u origin main
