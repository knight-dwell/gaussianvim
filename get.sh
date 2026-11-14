#!/usr/bin/env bash
# GaussianVim from nothing: installs git (if missing), clones the repo to ~/gaussianvim
# (or updates it) and runs the installer, which installs every other dependency.
#
#   curl -fsSL https://raw.githubusercontent.com/knight-dwell/gaussianvim/main/get.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/knight-dwell/gaussianvim/main/get.sh | bash -s -- --vim-only
#
# Anything after `--` goes to install.sh (--vim-only, --no-tex, --yes, --theme classic, ...).
# GV_DIR=/some/folder chooses where the repo goes.
set -euo pipefail
URL="https://github.com/knight-dwell/gaussianvim"
DIR="${GV_DIR:-$HOME/gaussianvim}"
have() { command -v "$1" >/dev/null 2>&1; }
SUDO=""; [[ $EUID -ne 0 ]] && have sudo && SUDO="sudo"

if ! have git || ! have curl; then
  echo "==> installing git and curl"
  if have apt-get; then $SUDO apt-get update -q && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -q git curl ca-certificates
  elif have dnf; then $SUDO dnf install -y git curl
  elif have pacman; then $SUDO pacman -Sy --needed --noconfirm git curl
  elif have zypper; then $SUDO zypper -n install git curl
  else echo "Install git and curl, then run this again."; exit 1; fi
fi

if [[ -d $DIR/.git ]]; then
  echo "==> updating $DIR"
  git -C "$DIR" pull --ff-only
else
  echo "==> downloading GaussianVim to $DIR"
  git clone --depth 1 "$URL" "$DIR"
fi
# piped from curl: give the installer the keyboard for its questions
if ( : </dev/tty ) 2>/dev/null; then exec "$DIR/install.sh" "$@" </dev/tty; fi
exec "$DIR/install.sh" "$@"
