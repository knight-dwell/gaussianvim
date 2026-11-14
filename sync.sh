#!/usr/bin/env bash
# Copy the live GaussianVim / GaussianTeX files on THIS machine into the repo
# (run before committing an update):   ./sync.sh && git add -A && git commit -m "..."
# install.sh does the opposite on a new machine.
set -euo pipefail
R="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$R/share"
rs() { rsync -a --delete --exclude '__pycache__' --exclude '*.pyc' "$@"; }
# the JNCASR thesis template (its logo and jncthesis.sty) stays on this machine only
# the config is a git repo with two looks (branches): material -> config/, classic -> config-classic/
CFG="$HOME/.config/gaussianvim"
if [[ $(git -C "$CFG" branch --show-current 2>/dev/null || echo material) != material ]]; then
  echo "switch to the Material look first (gv-theme material): config/ is the Material branch" >&2; exit 1
fi
rs --exclude ".git" --exclude "tex-templates/thesis-jncasr" "$CFG/" "$R/config/"
if git -C "$CFG" rev-parse --verify -q classic >/dev/null; then
  rm -rf "$R/config-classic" && mkdir -p "$R/config-classic"
  git -C "$CFG" archive classic | tar -x -C "$R/config-classic"
  rm -rf "$R/config-classic/tex-templates/thesis-jncasr"
fi
rs "$HOME/.local/share/gaussianvim/dictionary/" "$R/share/dictionary/"
rs "$HOME/.local/share/gaussianvim/brand/" "$R/share/brand/"
mkdir -p "$R/bin" "$R/applications"
mkdir -p "$R/share/zathura" && cp "$HOME/.config/zathura/zathurarc" "$R/share/zathura/zathurarc"
cp "$HOME/.local/share/gaussianvim/GUIDE.md" "$R/docs/GUIDE.md"
for b in gv gtex gv-dict vimhelp gv-theme gv-doctor; do
  if [[ -f $HOME/.local/bin/$b ]]; then cp "$HOME/.local/bin/$b" "$R/bin/$b"; fi
done
for d in gaussianvim gaussiantex gaussianvim-dictionary; do
  sed "s|$HOME|@HOME@|g" "$HOME/.local/share/applications/$d.desktop" > "$R/applications/$d.desktop"
done
echo "synced into $R"
