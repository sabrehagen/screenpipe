#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

echo "building tauri frontend export (screenpipe-app-tauri/out)..."
pushd screenpipe-app-tauri >/dev/null
  if command -v bun >/dev/null 2>&1; then
    bun install --frozen-lockfile
    bun run prebuild
    bun run build
  else
    echo "bun is required to build the desktop app frontend for the source upload."
    echo "install bun, then re-run: scripts/ppa/prepare-source.sh"
    exit 1
  fi
popd >/dev/null

echo "vendoring rust deps for workspace (debian/vendor-workspace)..."
rm -rf debian/vendor-workspace
mkdir -p debian/vendor-workspace
cargo vendor --locked debian/vendor-workspace >/dev/null

echo "vendoring rust deps for tauri app (debian/vendor-app)..."
rm -rf debian/vendor-app
mkdir -p debian/vendor-app
cargo vendor --locked --manifest-path screenpipe-app-tauri/src-tauri/Cargo.toml debian/vendor-app >/dev/null

echo "ok: vendor dirs + out/ are ready."
