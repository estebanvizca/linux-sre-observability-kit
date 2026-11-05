#!/usr/bin/env bash
# Publish only the reviewed Git commit, never local cache or secret files.
set -euo pipefail
cd "$(dirname "$0")/.."
GH=${GH:-gh}
command -v "$GH" >/dev/null || { echo "Install GitHub CLI or set GH to its path" >&2; exit 1; }
repo=estebanvizca/linux-sre-observability-kit
"$GH" auth status
if [ "$("$GH" api user --jq .login)" != estebanvizca ]; then
  echo "Authenticate as estebanvizca before publishing" >&2
  exit 1
fi
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Create and review a local commit before publishing" >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Commit reviewed changes before publishing" >&2
  exit 1
fi
if [ "$(git branch --show-current)" != main ]; then
  echo "Switch to the reviewed main branch before publishing" >&2
  exit 1
fi
if git ls-files | grep -Eq '(^|/)(\.cache|\.venv|\.env)(/|$)|(^|/)id_(ed25519|rsa)$'; then
  echo "Local state or credentials are tracked; remove them before publishing" >&2
  exit 1
fi
if git remote get-url origin >/dev/null 2>&1; then
  for remote_url in $(git remote get-url --all origin) $(git remote get-url --push --all origin); do
    case "$remote_url" in
      "https://github.com/$repo"|"https://github.com/$repo.git"|"git@github.com:$repo.git") ;;
      *) echo "origin must point to $repo" >&2; exit 1 ;;
    esac
  done
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
