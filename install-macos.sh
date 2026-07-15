#!/usr/bin/env bash
# Backward-compat shim: macOS is now handled by install.sh (OS is auto-detected).
# Kept so the previously published install-macos.sh URL keeps working.
set -eu

curl -fsSL https://raw.githubusercontent.com/viasite-ansible/ansible-role-zsh/master/install.sh | bash
