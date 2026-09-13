#!/usr/bin/env bash

#

# Artix Linux + XLibre + dwm installer

# UEFI / OpenRC / XFS / LightDM / PipeWire / ConnMan / Flatpak

#

# Default target: /dev/nvme0n1

# Default user:   mike

#

# WARNING: THIS SCRIPT ERASES THE SELECTED DISK.

#

set -Eeuo pipefail

###############################################################################

# Configuration

###############################################################################

TARGET_DISK="/dev/nvme0n1"

EFI_PART="${TARGET_DISK}p1"
ROOT_PART="${TARGET_DISK}p2"

MNT="/mnt"

DEFAULT_HOSTNAME="artix"
DEFAULT_USERNAME="mike"
DEFAULT_TIMEZONE="America/New_York"
DEFAULT_KEYMAP="us"
DEFAULT_LOCALE="en_US.UTF-8"

###############################################################################

# Helpers

###############################################################################

log() {
echo
echo "==> $*"
}

fail() {
echo
echo "============================================================"
echo "ERROR: $*"
echo "============================================================"
exit 1
}

cleanup_on_error() {
echo
echo "============================================================"
echo "INSTALLATION FAILED"
echo "============================================================"
echo
echo "The target system may be partially installed."
echo
}

trap cleanup_on_error ERR

###############################################################################

# Initial checks

###############################################################################

[[ "$EUID" -eq 0 ]] || fail "Run this installer as root."

[[ -b "$TARGET_DISK" ]] || 
fail "Target disk $TARGET_DISK does not exist."

if [[ ! -d /sys/firmware/efi ]]; then
fail "This system is not booted in UEFI mode. Reboot the live ISO in UEFI mode."
fi

###############################################################################

# Network check

###############################################################################

log "Checking network connectivity..."

if ! ping -c 1 -W 3 artixlinux.org >/dev/null 2>&1; then
fail "Network connectivity check failed."
fi

###############################################################################

# User configuration

###############################################################################

echo
echo "============================================================"
echo "SYSTEM CONFIGURATION"
echo "============================================================"
echo

read -r -p "Hostname [$DEFAULT_HOSTNAME]: " HOSTNAME
HOSTNAME="${HOSTNAME:-$DEFAULT_HOSTNAME}"

read -r -p "Username [$DEFAULT_USERNAME]: " USERNAME
USERNAME="${USERNAME:-$DEFAULT_USERNAME}"

read -r -p "Timezone [$DEFAULT_TIMEZONE]: " TIMEZONE
TIMEZONE="${TIMEZONE:-$DEFAULT_TIMEZONE}"

read -r -p "Keyboard layout [$DEFAULT_KEYMAP]: " KEYMAP
KEYMAP="${KEYMAP:-$DEFAULT_KEYMAP}"

read -r -p "Locale [$DEFAULT_LOCALE]: " LOCALE
LOCALE="${LOCALE:-$DEFAULT_LOCALE}"

###############################################################################

# Validate username

###############################################################################

if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
fail "Invalid username: $USERNAME"
fi

###############################################################################

# Collect user password

#

# This happens before the disk is touched.

###############################################################################

echo
echo "============================================================"
echo "USER PASSWORD"
echo "============================================================"
echo
echo "Set the password for '$USERNAME'."
echo
echo "This is the password you will use with sudo."
echo
echo "There is NO separate root password."
echo "The root account will remain locked."
echo

while true; do

```
printf "Password: "
read -r -s USER_PASSWORD
printf '\n'

if [[ -z "$USER_PASSWORD" ]]; then
    echo "Password cannot be empty."
    echo
    continue
fi

printf "Confirm password: "
read -r -s USER_PASSWORD_CONFIRM
printf '\n'

if [[ "$USER_PASSWORD" == "$USER_PASSWORD_CONFIRM" ]]; then
    unset USER_PASSWORD_CONFIRM
    break
fi

echo
echo "Passwords do not match. Try again."
echo
```

done

###############################################################################

# Disk confirmation

###############################################################################

echo
echo "============================================================"
echo "FINAL DISK CONFIRMATION"
echo "====================
