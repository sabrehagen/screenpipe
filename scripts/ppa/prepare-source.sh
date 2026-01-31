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

echo "vendoring rust deps for workspace (vendor-workspace)..."
rm -rf vendor-workspace
mkdir -p vendor-workspace
cargo vendor --locked vendor-workspace >/dev/null

echo "vendoring rust deps for tauri app (vendor-app)..."
rm -rf vendor-app
mkdir -p vendor-app
cargo vendor --locked --manifest-path screenpipe-app-tauri/src-tauri/Cargo.toml vendor-app >/dev/null

echo "ok: vendor dirs + out/ are ready."
