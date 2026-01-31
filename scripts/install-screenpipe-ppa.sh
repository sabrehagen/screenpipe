#!/usr/bin/env bash
set -euo pipefail

PPA_KEYID_HEX="0x5AECB6FDE33583A8"
KEYRING_PATH="/etc/apt/keyrings/sabrehagen-screenpipe-ppa.gpg"
LIST_PATH="/etc/apt/sources.list.d/sabrehagen-screenpipe-ppa.list"
PPA_LINE="deb [signed-by=${KEYRING_PATH}] https://ppa.launchpadcontent.net/sabrehagen/screenpipe/ubuntu noble main"

# Remove old Launchpad entries first so apt update can't fail on missing keys.
sudo rm -f \
  /etc/apt/sources.list.d/sabrehagen-ubuntu-screenpipe*.list \
  /etc/apt/sources.list.d/sabrehagen-ubuntu-screenpipe*.sources \
  /etc/apt/sources.list.d/*screenpipe*.list \
  /etc/apt/sources.list.d/*screenpipe*.sources

sudo apt-get update
sudo apt-get install -y curl gpg

sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=${PPA_KEYID_HEX}" \
  | sudo gpg --dearmor -o "${KEYRING_PATH}"
sudo chmod 0644 "${KEYRING_PATH}"

echo "${PPA_LINE}" | sudo tee "${LIST_PATH}" >/dev/null

sudo apt-get update
sudo apt-get install -y screenpipe screenpipe-cli screenpipe-gui

echo
echo "Installed. Smoke test:"
echo "  screenpipe-cli --help"
echo "  screenpipe --help"
