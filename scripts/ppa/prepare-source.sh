#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

echo "vendoring rust deps (single vendor dir)..."
rm -rf vendor
mkdir -p vendor
# workspace first
cargo vendor --locked vendor >/dev/null
# tauri app may have additional deps; vendor them into the same dir to avoid duplication
cargo vendor --locked --manifest-path screenpipe-app-tauri/src-tauri/Cargo.toml vendor >/dev/null

echo "pruning vendored crates that are irrelevant for linux PPA builds..."
# Launchpad builds are linux-only and network-restricted; keep the vendor dir minimal to reduce upload size.
# The vendored tree is often dominated by Windows-only crates + import libraries (winapi/windows*/webview2*).
rm -rf vendor/windows vendor/windows-* vendor/windows_* vendor/windows-sys vendor/windows-sys-* vendor/windows-targets vendor/winapi-* vendor/webview2-* vendor/webview2_* vendor/windows_x86_64_* vendor/windows_i686_* vendor/windows_aarch64_* vendor/windows-*-gnu vendor/windows-*-msvc 2>/dev/null || true

# Also drop Apple-only crates (significant size, never used in Ubuntu PPA builds).
rm -rf vendor/objc* vendor/cocoa* vendor/core-foundation* vendor/core-graphics* vendor/core-media-sys* vendor/core-video-sys* vendor/dispatch* vendor/metal* vendor/mach2* vendor/fsevent-sys* vendor/osakit* vendor/mac-notification-sys* vendor/nokhwa-bindings-macos* vendor/cidre* vendor/accessibility* 2>/dev/null || true

echo "building tauri frontend export (screenpipe-app-tauri/out)..."
pushd screenpipe-app-tauri >/dev/null
  if command -v bun >/dev/null 2>&1; then
    bun install --frozen-lockfile
    bun run prebuild
    bun run build
    # keep source tarball small: we only need the static export in out/
    rm -rf .next
    # keep the source tarball clean: we only need the static export in out/
    # leaving node_modules causes dpkg-source noise (e.g. "no final newline") and bloats the upload
    rm -rf node_modules
  else
    if [[ "${PPA_SKIP_FRONTEND:-}" == "1" ]]; then
      echo "bun not found; skipping frontend build because PPA_SKIP_FRONTEND=1"
    else
      echo "bun is required to build the desktop app frontend for the source upload."
      echo "install bun, then re-run: scripts/ppa/prepare-source.sh"
      echo "or set PPA_SKIP_FRONTEND=1 to skip this step (not valid for PPA uploads)."
      exit 1
    fi
  fi
popd >/dev/null

echo "ok: vendor + out/ are ready."
