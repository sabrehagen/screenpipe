## ppa packaging (ubuntu 24.04 / noble)

this repo includes debian packaging to publish:

- **`screenpipe-cli`**: the rust cli (from `screenpipe-server` bin `screenpipe`, installed as `/usr/bin/screenpipe-cli`)
- **`screenpipe-gui`**: the tauri desktop app (from `screenpipe-app-tauri/src-tauri` bin `screenpipe-app`, installed as `/usr/bin/screenpipe`)
- **`screenpipe`**: meta package that installs both `screenpipe-cli` and `screenpipe-gui`

launchpad builds are network-restricted, so the source upload must include:

- vendored rust deps in `debian/vendor-workspace` and `debian/vendor-app`
- prebuilt next static export in `screenpipe-app-tauri/out` (tauri embeds this at compile time)

### one-time setup on your machine

- create a launchpad account + ppa
- create and register a gpg key with launchpad
- install build tooling:

```bash
sudo apt update
sudo apt install -y devscripts debhelper dput gnupg
```

### bump version

edit `debian/changelog` (new entry for noble) before each upload.

### build + upload

```bash
scripts/ppa/upload-ppa.sh ppa:sabrehagen/screenpipe
```

### github actions (auto publish on tags)

the workflow `.github/workflows/ppa.yml` publishes to your launchpad ppa on tag pushes (`v*`).

add these github secrets:

- **`PPA_TARGET`**: `ppa:sabrehagen/screenpipe` (optional; workflow defaults to this)
- **`PPA_GPG_PRIVATE_KEY`**: ascii-armored private key (`gpg --export-secret-keys --armor KEYID`)
- **`PPA_GPG_PASSPHRASE`**: the private key passphrase
- **`PPA_GPG_KEYID`**: your signing key id / fingerprint (the one registered on launchpad)

### local build (binary debs)

```bash
scripts/ppa/prepare-source.sh
debuild -b -uc -us
```
