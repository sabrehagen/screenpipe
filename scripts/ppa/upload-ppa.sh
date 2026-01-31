#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: scripts/ppa/upload-ppa.sh ppa:yourlaunchpadid/yourppa"
  exit 1
fi

ppa_target="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

echo "building source package..."
scripts/ppa/build-source.sh

echo "uploading to $ppa_target..."

changes_file="$(ls -1 ../screenpipe_*source.changes 2>/dev/null | head -n 1 || true)"
if [[ -z "$changes_file" ]]; then
  changes_file="$(ls -1 ../screenpipe_*.changes 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "$changes_file" ]]; then
  echo "could not find .changes file in parent dir"
  exit 1
fi

dput "$ppa_target" "$changes_file"
echo "ok: uploaded $changes_file"
