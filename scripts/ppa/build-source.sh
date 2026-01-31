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

echo "ensuring orig tarball exists (required for 3.0 (quilt))..."
# debian/changelog version includes debian revision; orig tarball uses the upstream part
full_version="$(dpkg-parsechangelog -SVersion)"
upstream_version="${full_version%%-*}"
orig_tarball="../screenpipe_${upstream_version}.orig.tar.gz"

if [[ ! -f "$orig_tarball" ]]; then
  echo "creating $orig_tarball from current git tree..."
  # -n makes gzip output deterministic (no timestamp)
  git archive --format=tar --prefix="screenpipe-${upstream_version}/" HEAD | gzip -n > "$orig_tarball"
fi

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
