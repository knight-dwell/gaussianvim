#!/usr/bin/env bash
# Copy the live GaussianVim / GaussianTeX files on THIS machine into the repo
# (run before committing an update):   ./sync.sh && git add -A && git commit -m "..."
# install.sh does the opposite on a new machine.
set -euo pipefail
R="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$R/share"
rs() { rsync -a --delete --exclude '__pycache__' --exclude '*.pyc' "$@"; }
# the JNCASR thesis template (its logo and jncthesis.sty) stays on this machine only
rs --exclude "tex-templates/thesis-jncasr" "$HOME/.config/gaussianvim/" "$R/config/"
rs "$HOME/.local/share/gaussianvim/dictionary/" "$R/share/dictionary/"
rs "$HOME/.local/share/gaussianvim/brand/" "$R/share/brand/"
mkdir -p "$R/bin" "$R/applications"
mkdir -p "$R/share/zathura" && cp "$HOME/.config/zathura/zathurarc" "$R/share/zathura/zathurarc"
for b in gv gtex gv-dict vimhelp; do cp "$HOME/.local/bin/$b" "$R/bin/$b"; done
for d in gaussianvim gaussiantex gaussianvim-dictionary; do
  sed "s|$HOME|@HOME@|g" "$HOME/.local/share/applications/$d.desktop" > "$R/applications/$d.desktop"
done
echo "synced into $R"
