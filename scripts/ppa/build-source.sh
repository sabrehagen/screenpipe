#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

if [[ ! -f debian/changelog ]]; then
  echo "missing debian/changelog"
  exit 1
fi

echo "preparing generated sources (vendor + next out)..."
scripts/ppa/prepare-source.sh

echo "building source package..."
if [[ -n "${PPA_GPG_KEYID:-}" && -n "${PPA_GPG_PASSPHRASE:-}" ]]; then
  # non-interactive signing (for ci)
  debuild -S -sa \
    -k"$PPA_GPG_KEYID" \
    -p"gpg --batch --yes --pinentry-mode loopback --passphrase ${PPA_GPG_PASSPHRASE}"
else
  # interactive signing (local)
  debuild -S -sa
fi

echo "ok: source package created in parent dir."
