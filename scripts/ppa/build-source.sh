#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

# #region agent log (ppa packaging debug)
# prefer the repo-local cursor debug log when available; fallback to /tmp for CI runners.
default_debug_log_path="/home/jackson/repositories/sabrehagen/screenpipe/.cursor/debug.log"
if [[ -f "$default_debug_log_path" || -d "$(dirname "$default_debug_log_path")" ]]; then
  debug_log_path="${SCREENPIPE_DEBUG_LOG_PATH:-$default_debug_log_path}"
else
  debug_log_path="${SCREENPIPE_DEBUG_LOG_PATH:-/tmp/screenpipe-debug.ndjson}"
fi
ndjson_log() {
  # minimal NDJSON logger (no secrets). usage: ndjson_log hypothesisId location message data_json
  local hypothesis_id="${1:-unknown}"
  local location="${2:-unknown}"
  local message="${3:-}"
  local data_json="${4:-{}}"
  # keep formatting dead-simple to avoid malformed json
  mkdir -p "$(dirname "$debug_log_path")" 2>/dev/null || true
  printf '{"sessionId":"debug-session","runId":"pre-fix","hypothesisId":"%s","location":"%s","message":"%s","data":%s,"timestamp":%s}\n' \
    "$hypothesis_id" "$location" "$message" "$data_json" "$(date +%s%3N)" >> "$debug_log_path" 2>/dev/null || true
}

ndjson_log "A" "scripts/ppa/build-source.sh:entry" "build-source entry" \
  "$(printf '{"pwd":"%s","gitRef":"%s"}' "$(pwd)" "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)")"
# #endregion agent log

if [[ ! -f debian/changelog ]]; then
  echo "missing debian/changelog"
  exit 1
fi

# debian/changelog version includes debian revision; orig tarball uses the upstream part
full_version="$(dpkg-parsechangelog -SVersion)"
upstream_version="${full_version%%-*}"
debian_revision="${full_version#${upstream_version}}"

# #region agent log (ppa packaging debug)
ndjson_log "B" "scripts/ppa/build-source.sh:version" "parsed versions" \
  "$(printf '{"full":"%s","upstream":"%s","debianRevision":"%s","forceOrig":%s}' \
    "$full_version" "$upstream_version" "$debian_revision" \
    "$(test "${PPA_FORCE_ORIG:-0}" = "1" && echo true || echo false)")"
# #endregion agent log

stage_root="$(mktemp -d)"
stage_dir="$stage_root/screenpipe"
cleanup() {
  rm -rf "$stage_root"
}
trap cleanup EXIT

if [[ "${PPA_FORCE_ORIG:-0}" != "1" ]]; then
  echo "debian-only revision detected: reusing existing launchpad orig tarball..."

  orig_tarball="$stage_root/screenpipe_${upstream_version}.orig.tar.xz"
  orig_url="https://launchpad.net/~sabrehagen/+archive/ubuntu/screenpipe/+files/screenpipe_${upstream_version}.orig.tar.xz"

  echo "downloading existing orig tarball from launchpad..."
  # use -L because launchpad redirects to launchpadlibrarian.net
  curl -fsSL "$orig_url" -o "$orig_tarball"

  # #region agent log (ppa packaging debug)
  ndjson_log "D" "scripts/ppa/build-source.sh:orig-download" "downloaded existing orig tarball" \
    "$(printf '{"url":"%s","path":"%s","sha256":"%s","bytes":%s}' \
      "$orig_url" "$orig_tarball" \
      "$(sha256sum "$orig_tarball" 2>/dev/null | awk "{print \$1}" || echo "")" \
      "$(stat -c %s "$orig_tarball" 2>/dev/null || echo 0)")"
  # #endregion agent log

  echo "unpacking orig tarball..."
  tar -xJf "$orig_tarball" -C "$stage_root"

  # detect extracted dir (should be screenpipe-$upstream_version)
  extracted_dir="$stage_root/screenpipe-${upstream_version}"
  if [[ ! -d "$extracted_dir" ]]; then
    echo "expected extracted dir not found: $extracted_dir"
    echo "extracted dirs:"
    ls -1 "$stage_root" || true
    exit 1
  fi
  stage_dir="$extracted_dir"
  cd "$stage_dir"

  echo "syncing debian/ packaging into extracted upstream tree..."
  rsync -a --delete "$repo_root/debian/" "$stage_dir/debian/"

  echo "vendoring rust deps into debian/vendor for launchpad offline builds..."
  rm -rf "$stage_dir/debian/vendor"
  mkdir -p "$stage_dir/debian/vendor"
  # workspace first
  cargo vendor --locked "$stage_dir/debian/vendor" >/dev/null
  # note: we intentionally do NOT vendor tauri app deps here. launchpad uses cargo 1.75,
  # and some tauri transitive deps require newer cargo features (e.g. edition2024).
  # prune windows + apple crates to reduce debian.tar.xz size (launchpad is linux-only)
  rm -rf "$stage_dir/debian/vendor"/windows "$stage_dir/debian/vendor"/windows-* "$stage_dir/debian/vendor"/windows_* "$stage_dir/debian/vendor"/windows-sys "$stage_dir/debian/vendor"/windows-sys-* "$stage_dir/debian/vendor"/windows-targets "$stage_dir/debian/vendor"/winapi-* "$stage_dir/debian/vendor"/webview2-* "$stage_dir/debian/vendor"/webview2_* "$stage_dir/debian/vendor"/windows_x86_64_* "$stage_dir/debian/vendor"/windows_i686_* "$stage_dir/debian/vendor"/windows_aarch64_* "$stage_dir/debian/vendor"/windows-*-gnu "$stage_dir/debian/vendor"/windows-*-msvc 2>/dev/null || true
  rm -rf "$stage_dir/debian/vendor"/objc* "$stage_dir/debian/vendor"/cocoa* "$stage_dir/debian/vendor"/core-foundation* "$stage_dir/debian/vendor"/core-graphics* "$stage_dir/debian/vendor"/core-media-sys* "$stage_dir/debian/vendor"/core-video-sys* "$stage_dir/debian/vendor"/dispatch* "$stage_dir/debian/vendor"/metal* "$stage_dir/debian/vendor"/mach2* "$stage_dir/debian/vendor"/fsevent-sys* "$stage_dir/debian/vendor"/osakit* "$stage_dir/debian/vendor"/mac-notification-sys* "$stage_dir/debian/vendor"/nokhwa-bindings-macos* "$stage_dir/debian/vendor"/cidre* "$stage_dir/debian/vendor"/accessibility* 2>/dev/null || true

  echo "pruning vendored test assets to satisfy dpkg-source (no embedded binaries in debian.tar.xz)..."
  # dpkg-source (3.0 quilt) rejects binary files inside debian/ unless explicitly whitelisted.
  # none of these are needed for building the binaries.
  rm -rf \
    "$stage_dir/debian/vendor"/*/tests \
    "$stage_dir/debian/vendor"/*/test \
    "$stage_dir/debian/vendor"/*/benches \
    "$stage_dir/debian/vendor"/*/examples \
    "$stage_dir/debian/vendor"/*/fuzz \
    "$stage_dir/debian/vendor"/*/.github \
    "$stage_dir/debian/vendor"/*/ci \
    2>/dev/null || true
  find "$stage_dir/debian/vendor" -type f \( \
      -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.gif' -o -name '*.webp' -o -name '*.ico' -o -name '*.icns' \
      -o -name '*.ttf' -o -name '*.otf' -o -name '*.ttc' -o -name '*.woff' -o -name '*.woff2' \
      -o -name '*.tif' -o -name '*.tiff' -o -name '*.bmp' -o -name '*.wav' -o -name '*.mp3' -o -name '*.mp4' \
      -o -name '*.der' -o -name '*.p12' -o -name '*.key' -o -name '*.enc' -o -name '*.blb' -o -name '*.fst' -o -name '*.dll' \
      -o -name '*.dfa' -o -name '*.wasm' -o -name '*.pdf' -o -name '*.tar.xz' -o -name '*.tar.gz' -o -name '*.tar.bz2' \
      -o -name '*.bin' -o -name '*.raw' \
      -o -name '.DS_Store' \
    \) -delete 2>/dev/null || true

  if [[ "${PPA_VERIFY_ONLY:-}" == "1" ]]; then
    echo "preflight: running dpkg-source -b to validate source package (should fail if any unwanted binaries remain)..."
    # #region agent log (ppa packaging debug)
    ndjson_log "E" "scripts/ppa/build-source.sh:verify-only" "running dpkg-source -b (verify only)" \
      "$(printf '{"dir":"%s","mode":"debian-only"}' "$stage_dir")"
    # #endregion agent log
    dpkg-source -b .
    echo "preflight ok: dpkg-source accepted the tree"
    # #region agent log (ppa packaging debug)
    ndjson_log "E" "scripts/ppa/build-source.sh:verify-only" "dpkg-source ok (verify only)" \
      "$(printf '{"dir":"%s","mode":"debian-only"}' "$stage_dir")"
    # #endregion agent log
    exit 0
  fi

  echo "building source package (no orig reupload, -sd)..."
  if [[ "${PPA_NO_SIGN:-}" == "1" ]]; then
    ndjson_log "D" "scripts/ppa/build-source.sh:debuild" "debuild mode (debian-only no sign)" '{"mode":"-sd"}'
    debuild --no-lintian -S -sd -us -uc
  elif [[ -n "${PPA_GPG_KEYID:-}" && -n "${PPA_GPG_PASSPHRASE:-}" ]]; then
    ndjson_log "D" "scripts/ppa/build-source.sh:debuild" "debuild mode (debian-only signed)" '{"mode":"-sd"}'
    debuild --no-lintian -S -sd \
      -k"$PPA_GPG_KEYID" \
      -p"gpg --batch --yes --pinentry-mode loopback --passphrase ${PPA_GPG_PASSPHRASE}"
  else
    ndjson_log "D" "scripts/ppa/build-source.sh:debuild" "debuild mode (debian-only interactive)" '{"mode":"-sd"}'
    debuild --no-lintian -S -sd
  fi

  echo "copying built artifacts back to repo parent dir..."
  for f in "$stage_root"/screenpipe_*; do
    [[ -e "$f" ]] || continue
    mv -f "$f" "$repo_root/../"
  done

  echo "ok: source package created in parent dir."
  exit 0
fi

echo "staging linux ppa source tree (whitelist only)..."
mkdir -p "$stage_dir"

# Only include files/directories needed to build the Ubuntu PPA packages.
# Everything else (docs, windows blobs, caches, etc) is excluded from the staged tree by default.
rsync -a --delete --prune-empty-dirs \
  --include '/Cargo.toml' \
  --include '/Cargo.lock' \
  --include '/rust-toolchain.toml' \
  --include '/debian/***' \
  --include '/scripts/' \
  --include '/scripts/ppa/' \
  --include '/scripts/ppa/***' \
  --include '/screenpipe-*/***' \
  --include '/screenpipe-app-tauri/***' \
  --exclude '/screenpipe-audio/onnxruntime-win-*.zip' \
  --exclude '/screenpipe-app-tauri/src-tauri/onnxruntime-win-*' \
  --exclude '/screenpipe-app-tauri/.next/***' \
  --exclude '/**/node_modules/***' \
  --exclude '/**/target/***' \
  --exclude '/vendor/***' \
  --exclude '/vendor-workspace/***' \
  --exclude '/vendor-app/***' \
  --exclude '*' \
  ./ \
  "$stage_dir/"

cd "$stage_dir"

echo "preparing generated sources in staged tree (vendor + next out)..."
scripts/ppa/prepare-source.sh

# #region agent log (ppa packaging debug)
ndjson_log "A" "scripts/ppa/build-source.sh:after-prepare" "after prepare-source.sh" \
  "$(printf '{"vendorExists":%s,"outIndexExists":%s,"outIndexSha256":"%s"}' \
    "$(test -d vendor && echo true || echo false)" \
    "$(test -f screenpipe-app-tauri/out/index.html && echo true || echo false)" \
    "$(sha256sum screenpipe-app-tauri/out/index.html 2>/dev/null | awk "{print \$1}" || echo "")")"
# #endregion agent log

echo "ensuring orig tarball exists (required for 3.0 (quilt))..."
orig_tarball="$stage_root/screenpipe_${upstream_version}.orig.tar.xz"

echo "preflight: sizing orig tarball inputs (sanity check)..."
# this is approximate (filesystem du), but catches obvious bloat before we spend minutes compressing.
du -h -d 1 . | sort -hr | head -n 30
echo "preflight: key inputs"
du -h \
  vendor \
  screenpipe-app-tauri/out \
  screenpipe-app-tauri/.next \
  2>/dev/null || true

# fail fast unless explicitly overridden
max_bytes="${PPA_MAX_ORIG_BYTES:-0}"
if [[ "$max_bytes" != "0" ]]; then
  bytes="$(du -sb . | awk '{print $1}')"
  if [[ "$bytes" -gt "$max_bytes" ]]; then
    echo "preflight: aborting: source tree size ${bytes} bytes exceeds PPA_MAX_ORIG_BYTES=${max_bytes}"
    exit 1
  fi
fi

echo "creating $orig_tarball from prepared working tree..."
# NOTE: vendor/ and screenpipe-app-tauri/out/ are generated by prepare-source.sh.
# They must be part of the .orig tarball (upstream) so dpkg-source doesn't try to put binary blobs into debian.tar.xz.
# We exclude debian/ so it stays in the debian tarball, as expected for 3.0 (quilt).
# Remove any pre-existing orig tarball with other compression (e.g. .gz),
# otherwise dpkg-source/debuild may pick it up and cause huge uploads.
rm -f "../screenpipe_${upstream_version}.orig.tar."* "$orig_tarball"
tar \
  --sort=name \
  --mtime='UTC 1970-01-01' \
  --owner=0 --group=0 --numeric-owner \
  --exclude='./.git' \
  --exclude='./debian' \
  --exclude='./target' \
  --exclude='./**/node_modules' \
  --exclude='./**/node_modules/**' \
  --exclude='./screenpipe-app-tauri/node_modules' \
  --exclude='./screenpipe-app-tauri/node_modules/**' \
  -c . \
  --transform="s,^\\.,screenpipe-${upstream_version}," \
| xz -T0 -9e > "$orig_tarball"

# #region agent log (ppa packaging debug)
ndjson_log "B" "scripts/ppa/build-source.sh:orig" "orig tarball created" \
  "$(printf '{"path":"%s","sha256":"%s","bytes":%s}' \
    "$orig_tarball" \
    "$(sha256sum "$orig_tarball" 2>/dev/null | awk "{print \$1}" || echo "")" \
    "$(stat -c %s "$orig_tarball" 2>/dev/null || echo 0)")"
# #endregion agent log

echo "building source package..."
# dpkg-source will refuse "unrepresentable changes" if any build artifacts are present in-tree.
# make the source build hermetic by removing common build output dirs first.
rm -rf target screenpipe-app-tauri/src-tauri/target screenpipe-app-tauri/target

# allow fast local verification without gpg (ci always signs)
if [[ "${PPA_NO_SIGN:-}" == "1" ]]; then
  # default to -sd to avoid re-uploading orig.tar.xz for debian-only revisions (launchpad rejects changed orig).
  # use PPA_FORCE_ORIG=1 when uploading a brand new upstream version.
  if [[ "${PPA_FORCE_ORIG:-0}" == "1" ]]; then
    ndjson_log "C" "scripts/ppa/build-source.sh:debuild" "debuild mode (no sign)" '{"mode":"-sa"}'
    debuild --no-lintian -S -sa -us -uc
  else
    ndjson_log "C" "scripts/ppa/build-source.sh:debuild" "debuild mode (no sign)" '{"mode":"-sd"}'
    debuild --no-lintian -S -sd -us -uc
  fi
elif [[ -n "${PPA_GPG_KEYID:-}" && -n "${PPA_GPG_PASSPHRASE:-}" ]]; then
  # non-interactive signing (for ci)
  if [[ "${PPA_FORCE_ORIG:-0}" == "1" ]]; then
    ndjson_log "C" "scripts/ppa/build-source.sh:debuild" "debuild mode (signed)" '{"mode":"-sa"}'
    debuild --no-lintian -S -sa \
      -k"$PPA_GPG_KEYID" \
      -p"gpg --batch --yes --pinentry-mode loopback --passphrase ${PPA_GPG_PASSPHRASE}"
  else
    ndjson_log "C" "scripts/ppa/build-source.sh:debuild" "debuild mode (signed)" '{"mode":"-sd"}'
    debuild --no-lintian -S -sd \
      -k"$PPA_GPG_KEYID" \
      -p"gpg --batch --yes --pinentry-mode loopback --passphrase ${PPA_GPG_PASSPHRASE}"
  fi
else
  # interactive signing (local)
  if [[ "${PPA_FORCE_ORIG:-0}" == "1" ]]; then
    ndjson_log "C" "scripts/ppa/build-source.sh:debuild" "debuild mode (interactive)" '{"mode":"-sa"}'
    debuild --no-lintian -S -sa
  else
    ndjson_log "C" "scripts/ppa/build-source.sh:debuild" "debuild mode (interactive)" '{"mode":"-sd"}'
    debuild --no-lintian -S -sd
  fi
fi

echo "copying built artifacts back to repo parent dir..."
for f in "$stage_root"/screenpipe_*; do
  [[ -e "$f" ]] || continue
  mv -f "$f" "$repo_root/../"
done

echo "ok: source package created in parent dir."
