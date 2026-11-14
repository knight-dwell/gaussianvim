#!/usr/bin/env bash
# GaussianVim + GaussianTeX installer (Ubuntu / Debian, Fedora, Arch).
#
#   git clone git@github.com:knight-dwell/gaussianvim.git && cd gaussianvim && ./install.sh
#
# Options:
#   --yes        don't ask anything (install Claude Code too)
#   --no-tex     skip TeX Live, zathura (GaussianTeX needs them; ~1-2 GB)
#   --no-docs    skip the offline docs download (NumPy, Matplotlib, Python, ...; ~150 MB)
#   --no-wiki    skip the offline physics + maths Wikipedia (~650 MB; online Wikipedia still works)
#   --no-claude  don't offer Claude Code
#   --no-system  don't install system packages (no sudo needed); only copy GaussianVim
#
# Safe to run again (it updates). Your old ~/.config/gaussianvim is kept as a backup.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
NVIM_VERSION="v0.12.6"
G="$HOME/.local/share/gaussianvim"
BIN="$HOME/.local/bin"
YES=0 TEX=1 DOCS=1 CLAUDE=1 SYSTEM=1 WIKI=1
for a in "$@"; do
  case "$a" in
    --yes) YES=1 ;; --no-tex) TEX=0 ;; --no-docs) DOCS=0 ;; --no-claude) CLAUDE=0 ;; --no-system) SYSTEM=0 ;; --no-wiki) WIKI=0 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown option $a (see --help)"; exit 1 ;;
  esac
done

say()  { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
ask()  { [[ $YES == 1 ]] && return 0; read -r -p "    $1 [Y/n] " r; [[ -z $r || $r =~ ^[Yy] ]]; }

# ── 1. system packages ─────────────────────────────────────────────────────────
if [[ $SYSTEM == 1 ]]; then
  say "System packages (needs sudo)"
  if command -v apt-get >/dev/null; then
    PKGS=(git curl wget unzip zip rsync ripgrep fd-find build-essential gfortran
      python3 python3-pip python3-venv python3-gi gir1.2-gtk-3.0 gir1.2-webkit2-4.1
      python3-numpy python3-scipy python3-matplotlib python3-pil python3-tk
      xdotool zenity imagemagick ghostscript pandoc kitty nodejs npm fontconfig xclip)
    [[ $TEX == 1 ]] && PKGS+=(latexmk texlive-latex-extra texlive-science texlive-publishers
      texlive-bibtex-extra texlive-fonts-recommended texlive-pictures zathura zathura-pdf-poppler)
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${PKGS[@]}"
  elif command -v dnf >/dev/null; then
    PKGS=(git curl wget unzip zip rsync ripgrep fd-find gcc gcc-c++ make gcc-gfortran
      python3 python3-pip python3-gobject gtk3 webkit2gtk4.1
      python3-numpy python3-scipy python3-matplotlib python3-pillow python3-tkinter
      xdotool zenity ImageMagick ghostscript pandoc kitty nodejs npm fontconfig xclip)
    [[ $TEX == 1 ]] && PKGS+=(latexmk texlive-scheme-medium texlive-collection-latexextra texlive-collection-science
      texlive-collection-publishers texlive-collection-bibtexextra zathura zathura-pdf-mupdf)
    sudo dnf install -y "${PKGS[@]}"
  elif command -v pacman >/dev/null; then
    PKGS=(git curl wget unzip zip rsync ripgrep fd base-devel gcc-fortran python python-pip python-gobject gtk3
      webkit2gtk-4.1 python-numpy python-scipy python-matplotlib python-pillow tk xdotool zenity imagemagick
      ghostscript pandoc-cli kitty nodejs npm fontconfig xclip)
    [[ $TEX == 1 ]] && PKGS+=(texlive-basic texlive-latexextra texlive-science texlive-publishers texlive-bibtexextra
      texlive-fontsrecommended texlive-pictures zathura zathura-pdf-mupdf)
    sudo pacman -S --needed --noconfirm "${PKGS[@]}"
  else
    note "Unknown package manager: install git curl ripgrep fd python3 (numpy scipy matplotlib pillow tk,"
    note "PyGObject + WebKit2GTK 4.1), xdotool zenity imagemagick pandoc kitty nodejs npm, and for LaTeX:"
    note "latexmk, a TeX Live with revtex/nature/physics, zathura. Then run ./install.sh --no-system"
  fi
fi

# ── 2. Neovim (its own copy, so the system one is never touched) ───────────────
say "Neovim $NVIM_VERSION"
mkdir -p "$G" "$BIN"
if [[ ! -x "$G/nvim-${NVIM_VERSION#v}/bin/nvim" ]]; then
  arch=$(uname -m); [[ $arch == aarch64 ]] && arch=arm64
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/neovim/neovim/releases/download/$NVIM_VERSION/nvim-linux-$arch.tar.gz" -o "$tmp/nvim.tgz"
  tar -xzf "$tmp/nvim.tgz" -C "$tmp"
  rm -rf "$G/nvim-${NVIM_VERSION#v}"
  mv "$tmp/nvim-linux-$arch" "$G/nvim-${NVIM_VERSION#v}"
  rm -rf "$tmp"
fi
ln -sfn "$G/nvim-${NVIM_VERSION#v}" "$G/nvim"
note "$("$G/nvim/bin/nvim" --version | head -1)"

# ── 3. GaussianVim files ───────────────────────────────────────────────────────
say "GaussianVim + GaussianTeX files"
CONF="$HOME/.config/gaussianvim"
if [[ -d $CONF && ! -L $CONF ]] && ! diff -rq "$REPO/config" "$CONF" >/dev/null 2>&1; then
  backup="$CONF.backup-$(date +%Y%m%d-%H%M%S)"
  cp -a "$CONF" "$backup"
  note "old config kept in $backup"
fi
mkdir -p "$CONF"
rsync -a "$REPO/config/" "$CONF/"
rsync -a --delete "$REPO/share/dictionary/" "$G/dictionary/"
rsync -a "$REPO/share/brand/" "$G/brand/"
cp "$REPO/docs/GUIDE.md" "$G/GUIDE.md"          # :GvGuide in gv
if [[ ! -f $HOME/.config/zathura/zathurarc ]]; then      # the PDF viewer GaussianTeX opens
  mkdir -p "$HOME/.config/zathura" && cp "$REPO/share/zathura/zathurarc" "$HOME/.config/zathura/zathurarc"
fi
for b in "$REPO"/bin/*; do install -m 755 "$b" "$BIN/"; done
mkdir -p "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/scalable/apps"
cp "$G/brand/gaussianvim.svg" "$G/brand/gaussiantex.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/"
for d in "$REPO"/applications/*.desktop; do
  sed "s|@HOME@|$HOME|g" "$d" > "$HOME/.local/share/applications/$(basename "$d")"
done
command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
mkdir -p "$HOME/GaussianTeX"

# ~/.local/bin on PATH (Ubuntu adds it only when it exists at login)
if [[ ":$PATH:" != *":$BIN:"* ]]; then
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -f $rc ]] && ! grep -q 'GaussianVim: ~/.local/bin' "$rc" &&
      printf '\n# GaussianVim: ~/.local/bin on PATH\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
  done
  export PATH="$BIN:$PATH"
  note "added ~/.local/bin to PATH (open a new terminal)"
fi

# ── 4. a Nerd Font (the icons) ─────────────────────────────────────────────────
if ! fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd"; then
  say "JetBrainsMono Nerd Font (icons)"
  fdir="$HOME/.local/share/fonts/JetBrainsMonoNerd"; mkdir -p "$fdir"
  curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" -o /tmp/gv-font.zip
  unzip -oq /tmp/gv-font.zip -d "$fdir" && rm -f /tmp/gv-font.zip
  fc-cache -f >/dev/null
fi
if command -v kitty >/dev/null && [[ ! -f $HOME/.config/kitty/kitty.conf ]]; then
  mkdir -p "$HOME/.config/kitty"
  printf '# written by the GaussianVim installer\nfont_family JetBrainsMono Nerd Font\nfont_size 11\n' > "$HOME/.config/kitty/kitty.conf"
  note "kitty: JetBrainsMono Nerd Font"
fi

[[ -n ${GV_INSTALL_TEST:-} ]] && { say "test mode: stopping before plugins"; exit 0; }

# ── 5. plugins, language servers ───────────────────────────────────────────────
say "Plugins and language servers (a few minutes)"
export NVIM_APPNAME=gaussianvim
# a recent tree-sitter CLI (builds the latex parser that typesets $maths$ in Markdown)
if command -v npm >/dev/null && ! tree-sitter --version 2>/dev/null | grep -qE " 0\.(2[6-9]|[3-9][0-9])"; then
  npm install -g --prefix "$HOME/.local" tree-sitter-cli >/dev/null 2>&1 || note "tree-sitter CLI didn't install (maths in Markdown stays as text)"
fi
"$G/nvim/bin/nvim" --headless "+Lazy! restore" +qa 2>/dev/null || "$G/nvim/bin/nvim" --headless "+Lazy! sync" +qa
"$G/nvim/bin/nvim" --headless -c 'lua require("nvim-treesitter").install({ "latex" }):wait(300000)' -c qa 2>/dev/null || true
"$G/nvim/bin/nvim" --headless -c "MasonInstall basedpyright ruff clangd bash-language-server lua-language-server fortls texlab ltex-ls-plus debugpy" -c qa || \
  note "some language servers didn't install; open gv and run :Mason"

# ── 6. offline docs ────────────────────────────────────────────────────────────
if [[ $DOCS == 1 ]]; then
  say "Offline docs: NumPy, Matplotlib, Python, pandas, LaTeX, Fortran, Bash + SciPy (~150 MB)"
  "$G/nvim/bin/nvim" --headless -c 'lua local d=false; require("gv.docs").install(nil, function() d=true end); vim.wait(1800000, function() return d end, 500); vim.wait(120000, function() return vim.uv.fs_stat(vim.fn.stdpath("data").."/docs/pydoc-scipy.json") ~= nil end, 500)' -c qa || \
    note "docs download failed; in gv: :GvDocs install"
fi

# ── 6b. offline Wikipedia (physics + maths, Kiwix) ─────────────────────────────
python3 -m pip install --user --quiet libzim 2>/dev/null || python3 -m pip install --user --quiet --break-system-packages libzim 2>/dev/null || \
  note "libzim didn't install: offline Wikipedia needs  pip install --user libzim"
if [[ $WIKI == 1 ]]; then
  say "Offline physics + maths Wikipedia (~650 MB)"
  "$G/nvim/bin/nvim" --headless -c 'lua require("gv.wiki").install(); vim.wait(3600000, function() return #vim.fn.glob(vim.fn.stdpath("data").."/wiki/*.part", false, true) == 0 and #vim.fn.glob(vim.fn.stdpath("data").."/wiki/*.zim", false, true) >= 2 end, 2000)' -c qa || \
    note "Wikipedia download failed; in gv: :GvWiki install"
fi

# ── 7. Claude Code (Space a a in gv) ───────────────────────────────────────────
if [[ $CLAUDE == 1 ]] && ! command -v claude >/dev/null && [[ ! -x $HOME/.local/bin/claude ]]; then
  say "Claude Code (the AI panel: Space a a)"
  if ask "Install Claude Code from claude.ai?"; then
    curl -fsSL https://claude.ai/install.sh | bash || note "Claude Code didn't install; later: curl -fsSL https://claude.ai/install.sh | bash"
    note "run  claude  once in a terminal to log in"
  fi
fi

# ── 8. Super+? opens the dictionary (GNOME) ────────────────────────────────────
if command -v gsettings >/dev/null && [[ ${XDG_CURRENT_DESKTOP:-} == *GNOME* ]]; then
  base=org.gnome.settings-daemon.plugins.media-keys
  path=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/gaussianvim-dict/
  list=$(gsettings get $base custom-keybindings)
  if [[ $list != *gaussianvim-dict* ]]; then
    if [[ $list == "@as []" || $list == "[]" ]]; then new="['$path']"; else new="${list%]}, '$path']"; fi
    gsettings set $base custom-keybindings "$new"
    gsettings set $base.custom-keybinding:$path name "GaussianVim Dictionary"
    gsettings set $base.custom-keybinding:$path command "$BIN/gv-dict"
    gsettings set $base.custom-keybinding:$path binding "<Super>question"
    note "Super+? opens the GaussianVim Dictionary"
  fi
fi

say "Done"
note "gv            GaussianVim (or the GaussianVim app)        gtex   LaTeX projects (GaussianTeX app)"
note "gv-dict       every key and alias (Super+?, Space ? in gv)"
note "The guide: $REPO/docs/GUIDE.md"
command -v claude >/dev/null || [[ -x $HOME/.local/bin/claude ]] || note "Claude panel needs Claude Code: curl -fsSL https://claude.ai/install.sh | bash"
