#!/usr/bin/env bash
# GaussianVim + GaussianTeX installer. Works on a fresh Linux: it installs every
# dependency it needs (Ubuntu / Debian / Mint / Pop, Fedora / RHEL, Arch / Manjaro,
# openSUSE), its own Neovim, and a recent Node when the system one is too old.
#
#   From nothing (installs git, clones, runs this):
#     curl -fsSL https://raw.githubusercontent.com/knight-dwell/gaussianvim/main/get.sh | bash
#   From a clone:
#     ./install.sh              GaussianVim + GaussianTeX (LaTeX), everything
#     ./install-gv.sh           GaussianVim only (the editor; no TeX Live, no offline Wikipedia)
#
# Options:
#   --vim-only   GaussianVim only (same as ./install-gv.sh)
#   --yes        don't ask anything (install Claude Code too)
#   --theme material|classic   the look to start with (default: material; switch later: gv-theme)
#   --no-tex     skip TeX Live, zathura (GaussianTeX needs them; ~1-2 GB)
#   --no-docs    skip the offline docs download (NumPy, Matplotlib, Python, ...; ~150 MB)
#   --no-wiki    skip the offline physics + maths Wikipedia (~650 MB; online Wikipedia still works)
#   --no-claude  don't offer Claude Code
#   --no-system  don't install system packages (no sudo needed); only GaussianVim itself
#
# Safe to run again (it updates). Your config changes are kept in its git history.
# Afterwards `gv-doctor` checks that everything is in place.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
NVIM_VERSION="v0.12.6"
NODE_MAJOR=22
G="$HOME/.local/share/gaussianvim"
BIN="$HOME/.local/bin"
CONF="$HOME/.config/gaussianvim"
YES=0 TEX=1 DOCS=1 CLAUDE=1 SYSTEM=1 WIKI=1 VIMONLY=0 THEME=material
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) YES=1 ;; --no-tex) TEX=0 ;; --no-docs) DOCS=0 ;; --no-claude) CLAUDE=0 ;;
    --no-system) SYSTEM=0 ;; --no-wiki) WIKI=0 ;;
    --vim-only) VIMONLY=1 TEX=0 WIKI=0 ;;
    --theme) THEME=${2:-}; shift ;;
    --theme=*) THEME=${1#--theme=} ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    *) echo "unknown option $1 (see --help)"; exit 1 ;;
  esac
  shift
done
[[ $THEME == material || $THEME == classic ]] || { echo "--theme is material or classic"; exit 1; }

say()  { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$*"; }
# questions read the keyboard even when this runs from `curl ... | bash`
ask() {
  [[ $YES == 1 ]] && return 0
  [[ -r /dev/tty ]] || return 0
  local r=""
  read -r -p "    $1 [Y/n] " r </dev/tty || r=""
  [[ -z $r || $r =~ ^[Yy] ]]
}
have() { command -v "$1" >/dev/null 2>&1; }

[[ $(uname -s) == Linux ]] || { echo "GaussianVim installs on Linux."; exit 1; }
case "$(uname -m)" in
  x86_64|amd64) NV_ARCH=x86_64 NODE_ARCH=x64 ;;
  aarch64|arm64) NV_ARCH=arm64 NODE_ARCH=arm64 ;;
  *) echo "Unsupported CPU: $(uname -m) (x86_64 and arm64 only)"; exit 1 ;;
esac

# sudo: not needed as root; without it the system packages are skipped
SUDO=""
if [[ $SYSTEM == 1 && $EUID -ne 0 ]]; then
  if have sudo; then SUDO="sudo"
  else warn "no sudo: skipping system packages (see --help for the list, or ask an admin)"; SYSTEM=0; fi
fi

# ── 1. system packages ─────────────────────────────────────────────────────────
# What each distribution calls things; "a|b" = a, or b where a doesn't exist.
# Names a release doesn't have are skipped (with a note) instead of failing the install.
APT_BASE=(git curl wget ca-certificates unzip zip xz-utils tar rsync ripgrep fd-find build-essential gfortran
  python3 python3-pip python3-venv python3-gi python3-gi-cairo gir1.2-gtk-3.0 gir1.2-vte-2.91
  "gir1.2-webkit2-4.1|gir1.2-webkit2-4.0" python3-numpy python3-scipy python3-matplotlib python3-pil python3-tk
  xdotool zenity imagemagick ghostscript poppler-utils pandoc kitty fontconfig xclip wl-clipboard gh)
APT_TEX=(latexmk texlive-latex-extra texlive-science texlive-publishers texlive-bibtex-extra
  texlive-fonts-recommended texlive-pictures zathura zathura-pdf-poppler)
DNF_BASE=(git curl wget ca-certificates unzip zip xz tar rsync ripgrep fd-find gcc gcc-c++ make gcc-gfortran
  python3 python3-pip python3-gobject gtk3 vte291 "webkit2gtk4.1|webkit2gtk4.0|webkit2gtk3"
  python3-numpy python3-scipy python3-matplotlib python3-pillow python3-tkinter
  xdotool zenity ImageMagick ghostscript poppler-utils pandoc kitty fontconfig xclip wl-clipboard gh)
DNF_TEX=(latexmk texlive-scheme-medium texlive-collection-latexextra texlive-collection-science
  texlive-collection-publishers texlive-collection-bibtexextra zathura "zathura-pdf-poppler|zathura-pdf-mupdf")
PAC_BASE=(git curl wget ca-certificates unzip zip xz tar rsync ripgrep fd base-devel gcc-fortran
  python python-pip python-gobject gtk3 vte3 webkit2gtk-4.1 python-numpy python-scipy python-matplotlib
  python-pillow tk xdotool zenity imagemagick ghostscript poppler "pandoc-cli|pandoc" kitty fontconfig xclip wl-clipboard github-cli)
PAC_TEX=(texlive-basic texlive-latex texlive-latexextra texlive-binextra texlive-science texlive-publishers
  texlive-bibtexextra texlive-fontsrecommended texlive-pictures zathura "zathura-pdf-poppler|zathura-pdf-mupdf")
ZYP_BASE=(git curl wget ca-certificates unzip zip xz tar rsync ripgrep fd gcc gcc-c++ make gcc-fortran
  python3 python3-pip python3-gobject python3-gobject-Gdk typelib-1_0-Gtk-3_0 "typelib-1_0-Vte-2.91|typelib-1_0-Vte-2_91"
  "typelib-1_0-WebKit2-4_1|typelib-1_0-WebKit2-4_0" python3-numpy python3-scipy python3-matplotlib python3-Pillow
  python3-tk xdotool zenity ImageMagick ghostscript poppler-tools pandoc kitty fontconfig xclip wl-clipboard gh)
ZYP_TEX=(texlive-latexmk texlive-scheme-medium texlive-collection-latexextra texlive-collection-science
  texlive-collection-publishers texlive-collection-bibtexextra zathura zathura-plugin-pdf-poppler)

# keep the names this system has:  pick <exists-function> names...  -> PICKED, SKIPPED
PICKED=() SKIPPED=()
pick() {
  local exists=$1 item alt found
  local -a alts
  shift
  PICKED=() SKIPPED=()
  for item in "$@"; do
    found=""
    IFS='|' read -ra alts <<<"$item"
    for alt in "${alts[@]}"; do
      if "$exists" "$alt"; then found=$alt; break; fi
    done
    if [[ -n $found ]]; then PICKED+=("$found"); else SKIPPED+=("$item"); fi
  done
}
apt_has() { apt-cache policy "$1" 2>/dev/null | grep -q 'Candidate: [^(]'; }
dnf_has() { rpm -q "$1" >/dev/null 2>&1 || dnf -q list --available "$1" >/dev/null 2>&1; }
pac_has() { pacman -Qi "$1" >/dev/null 2>&1 || pacman -Si "$1" >/dev/null 2>&1; }
zyp_has() { zypper -q -n search -x -t package "$1" >/dev/null 2>&1; }

if [[ $SYSTEM == 1 ]]; then
  say "System packages (needs sudo)"
  LIST=()
  if have apt-get; then
    $SUDO apt-get update -q
    LIST=("${APT_BASE[@]}"); if [[ $TEX == 1 ]]; then LIST+=("${APT_TEX[@]}"); fi
    pick apt_has "${LIST[@]}"
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${PICKED[@]}"
  elif have dnf; then
    LIST=("${DNF_BASE[@]}"); if [[ $TEX == 1 ]]; then LIST+=("${DNF_TEX[@]}"); fi
    pick dnf_has "${LIST[@]}"
    $SUDO dnf install -y "${PICKED[@]}"
  elif have pacman; then
    $SUDO pacman -Sy --noconfirm >/dev/null
    LIST=("${PAC_BASE[@]}"); if [[ $TEX == 1 ]]; then LIST+=("${PAC_TEX[@]}"); fi
    pick pac_has "${LIST[@]}"
    $SUDO pacman -S --needed --noconfirm "${PICKED[@]}"
  elif have zypper; then
    $SUDO zypper -q -n refresh || true
    LIST=("${ZYP_BASE[@]}"); if [[ $TEX == 1 ]]; then LIST+=("${ZYP_TEX[@]}"); fi
    pick zyp_has "${LIST[@]}"
    $SUDO zypper -n install --no-recommends "${PICKED[@]}"
  else
    warn "Unknown package manager. Install by hand: git curl ripgrep fd python3 (numpy scipy matplotlib"
    warn "pillow tk, PyGObject with GTK 3, VTE 2.91, WebKit2GTK 4.1), xdotool zenity imagemagick poppler"
    warn "pandoc, a C compiler, and for LaTeX: latexmk, TeX Live with revtex, zathura. Then: ./install.sh --no-system"
  fi
  if [[ ${#SKIPPED[@]} -gt 0 ]]; then note "not available on this system (skipped): ${SKIPPED[*]}"; fi
fi
for c in git curl tar; do have $c || { echo "$c is needed; install it and run again."; exit 1; }; done

# ── 2. Neovim (its own copy, so the system one is never touched) ───────────────
say "Neovim $NVIM_VERSION"
mkdir -p "$G" "$BIN"
if [[ ! -x "$G/nvim-${NVIM_VERSION#v}/bin/nvim" ]]; then
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/neovim/neovim/releases/download/$NVIM_VERSION/nvim-linux-$NV_ARCH.tar.gz" -o "$tmp/nvim.tgz"
  tar -xzf "$tmp/nvim.tgz" -C "$tmp"
  rm -rf "$G/nvim-${NVIM_VERSION#v}"
  mv "$tmp/nvim-linux-$NV_ARCH" "$G/nvim-${NVIM_VERSION#v}"
  rm -rf "$tmp"
fi
ln -sfn "$G/nvim-${NVIM_VERSION#v}" "$G/nvim"
note "$("$G/nvim/bin/nvim" --version | head -1)"

# ── 2b. Node (language servers need >= 18; Ubuntu 22.04 ships 12) ──────────────
node_ok() { local v; v=$("$1" -v 2>/dev/null) || return 1; v=${v#v}; [[ ${v%%.*} -ge 18 ]]; }
if node_ok node; then
  note "Node $(node -v)"
elif node_ok "$G/node/bin/node"; then
  note "Node $("$G/node/bin/node" -v) (GaussianVim's own)"
else
  say "Node $NODE_MAJOR (GaussianVim's own copy: the system one is missing or too old)"
  base="https://nodejs.org/dist/latest-v$NODE_MAJOR.x"
  file=$(curl -fsSL "$base/SHASUMS256.txt" 2>/dev/null | awk '{print $2}' | grep -E "^node-v[0-9.]+-linux-$NODE_ARCH\.tar\.xz$" | head -1 || true)
  if [[ -n $file ]] && have xz; then
    tmp=$(mktemp -d)
    if curl -fsSL "$base/$file" -o "$tmp/node.tar.xz" && tar -xJf "$tmp/node.tar.xz" -C "$tmp"; then
      rm -rf "$G/node" && mv "$tmp/${file%.tar.xz}" "$G/node"
      note "$("$G/node/bin/node" -v) in $G/node"
    fi
    rm -rf "$tmp"
  else
    warn "couldn't fetch Node (no xz, or offline): language servers that need Node won't install"
  fi
fi
if [[ -x $G/node/bin/node ]]; then export PATH="$G/node/bin:$PATH"; fi

# ── 3. GaussianVim files ───────────────────────────────────────────────────────
say "GaussianVim files"
gitc() { git -C "$CONF" -c user.name=GaussianVim -c user.email=gaussianvim@localhost "$@"; }
firsttime=1; [[ -f $G/.installed ]] && firsttime=0
mkdir -p "$CONF"
if [[ ! -d $CONF/.git && -n $(ls -A "$CONF") ]]; then
  backup="$CONF.backup-$(date +%Y%m%d-%H%M%S)"
  cp -a "$CONF" "$backup"
  note "old config kept in $backup"
fi
# The config is a git repo with the two looks as branches: material (config/) and
# classic (config-classic/). Every update is a commit, so nothing is ever lost.
if [[ ! -d $CONF/.git ]]; then
  git init -q "$CONF"
  gitc checkout -q -b material
fi
prev=$(gitc branch --show-current 2>/dev/null || true)
if [[ -n $(gitc status --porcelain) ]]; then
  gitc add -A; gitc commit -qm "Your changes before the update" || true
fi
if gitc rev-parse --verify -q material >/dev/null; then gitc checkout -q material; fi
rsync -a "$REPO/config/" "$CONF/"
gitc add -A; gitc commit -qm "GaussianVim update $(date +%F)" >/dev/null || true
if ! gitc rev-parse --verify -q material >/dev/null; then gitc checkout -q -b material; fi   # older installs: one plain branch
gitc branch -f main material 2>/dev/null || true
# the classic look, written straight into its branch (no checkout needed)
if [[ -d $REPO/config-classic ]]; then
  idx=$(mktemp -u)
  tree=$(cd "$REPO/config-classic" && GIT_INDEX_FILE=$idx git --git-dir="$CONF/.git" --work-tree=. add -A >/dev/null &&
         GIT_INDEX_FILE=$idx git --git-dir="$CONF/.git" write-tree) || tree=""
  rm -f "$idx"
  if [[ -n $tree ]]; then
    parent=$(gitc rev-parse --verify -q classic || gitc rev-parse material)
    if [[ $(gitc rev-parse "$parent^{tree}") != "$tree" ]]; then
      gitc branch -f classic "$(gitc commit-tree "$tree" -p "$parent" -m "GaussianVim classic look, update $(date +%F)")"
    fi
  fi
fi
# the look: --theme on a first install, else the one you were using
want=$prev
if [[ $firsttime == 1 || ( $want != material && $want != classic ) ]]; then want=$THEME; fi
gitc rev-parse --verify -q "$want" >/dev/null || want=material
gitc checkout -q "$want"
note "look: $want   (switch: gv-theme material | classic, or Space u T in gv)"

rsync -a --delete "$REPO/share/dictionary/" "$G/dictionary/"
rsync -a "$REPO/share/brand/" "$G/brand/"
cp "$REPO/docs/GUIDE.md" "$G/GUIDE.md"          # :GvGuide in gv
if [[ $TEX == 1 && ! -f $HOME/.config/zathura/zathurarc ]]; then      # the PDF viewer GaussianTeX opens
  mkdir -p "$HOME/.config/zathura" && cp "$REPO/share/zathura/zathurarc" "$HOME/.config/zathura/zathurarc"
fi
for b in "$REPO"/bin/*; do install -m 755 "$b" "$BIN/"; done
mkdir -p "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/scalable/apps"
cp "$G/brand/gaussianvim.svg" "$G/brand/gaussiantex.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/"
for d in "$REPO"/applications/*.desktop; do
  if [[ $VIMONLY == 1 && $(basename "$d") == gaussiantex.desktop ]]; then continue; fi
  sed "s|@HOME@|$HOME|g" "$d" > "$HOME/.local/share/applications/$(basename "$d")"
done
"$BIN/gv-theme" --launchers || true            # launchers for the look and the terminal this system has
if have update-desktop-database; then update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true; fi
if [[ $VIMONLY == 0 ]]; then mkdir -p "$HOME/GaussianTeX"; fi
if [[ $VIMONLY == 1 ]]; then echo vim > "$G/install-profile"; else echo full > "$G/install-profile"; fi   # for gv-doctor

# ~/.local/bin on PATH (Ubuntu adds it only when it exists at login)
if [[ ":$PATH:" != *":$BIN:"* ]]; then
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [[ -f $rc ]] && ! grep -q 'GaussianVim: ~/.local/bin' "$rc"; then
      printf '\n# GaussianVim: ~/.local/bin on PATH\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
    fi
  done
  if [[ -d $HOME/.config/fish ]] && ! grep -qs 'GaussianVim' "$HOME/.config/fish/config.fish"; then
    printf '\n# GaussianVim: ~/.local/bin on PATH\nfish_add_path $HOME/.local/bin\n' >> "$HOME/.config/fish/config.fish"
  fi
  export PATH="$BIN:$PATH"
  note "added ~/.local/bin to PATH (open a new terminal)"
fi

# ── 4. a Nerd Font (the icons) ─────────────────────────────────────────────────
if ! fc-list 2>/dev/null | grep -qi "Nerd Font"; then
  say "JetBrainsMono Nerd Font (icons)"
  fdir="$HOME/.local/share/fonts/JetBrainsMonoNerd"; mkdir -p "$fdir"
  tmp=$(mktemp -d)
  if have unzip && curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" -o "$tmp/font.zip"; then
    unzip -oq "$tmp/font.zip" -d "$fdir"; fc-cache -f >/dev/null 2>&1 || true
  else
    warn "font download failed: icons show as boxes until a Nerd Font is installed"
  fi
  rm -rf "$tmp"
fi
if have kitty && [[ ! -f $HOME/.config/kitty/kitty.conf ]]; then
  mkdir -p "$HOME/.config/kitty"
  printf '# written by the GaussianVim installer\nfont_family JetBrainsMono Nerd Font\nfont_size 11\n' > "$HOME/.config/kitty/kitty.conf"
  note "kitty: JetBrainsMono Nerd Font"
fi

# ── 4b. Python packages the distribution may lack (pip, for this user only) ────
pipi() { python3 -m pip install --user --quiet "$@" 2>/dev/null || python3 -m pip install --user --quiet --break-system-packages "$@" 2>/dev/null; }
if have python3; then
  python3 -c "import numpy, scipy, matplotlib" 2>/dev/null || pipi numpy scipy matplotlib pillow || \
    note "numpy / scipy / matplotlib didn't install (plots in the run card need them)"
  python3 -c "import libzim" 2>/dev/null || pipi libzim || \
    note "libzim didn't install: offline Wikipedia needs  pip install --user libzim"
fi

[[ -n ${GV_INSTALL_TEST:-} ]] && { say "test mode: stopping before plugins"; exit 0; }

# ── 5. plugins, language servers ───────────────────────────────────────────────
say "Plugins and language servers (a few minutes)"
export NVIM_APPNAME=gaussianvim
# a recent tree-sitter CLI (builds the latex parser that typesets $maths$ in Markdown)
if have npm && ! tree-sitter --version 2>/dev/null | grep -qE " 0\.(2[6-9]|[3-9][0-9])"; then
  npm install -g --prefix "$HOME/.local" tree-sitter-cli >/dev/null 2>&1 || note "tree-sitter CLI didn't install (maths in Markdown stays as text)"
fi
"$G/nvim/bin/nvim" --headless "+Lazy! restore" +qa 2>/dev/null || "$G/nvim/bin/nvim" --headless "+Lazy! sync" +qa
"$G/nvim/bin/nvim" --headless -c 'lua require("nvim-treesitter").install({ "latex" }):wait(300000)' -c qa 2>/dev/null || true
SERVERS="basedpyright ruff clangd bash-language-server lua-language-server fortls"
if [[ $TEX == 1 ]]; then SERVERS="$SERVERS texlab ltex-ls-plus"; fi
"$G/nvim/bin/nvim" --headless -c "MasonInstall $SERVERS debugpy" -c qa || \
  note "some language servers didn't install; open gv and run :Mason"

# ── 6. offline docs ────────────────────────────────────────────────────────────
if [[ $DOCS == 1 ]]; then
  say "Offline docs: NumPy, Matplotlib, Python, pandas, LaTeX, Fortran, Bash + SciPy (~150 MB)"
  "$G/nvim/bin/nvim" --headless -c 'lua local d=false; require("gv.docs").install(nil, function() d=true end); vim.wait(1800000, function() return d end, 500); vim.wait(120000, function() return vim.uv.fs_stat(vim.fn.stdpath("data").."/docs/pydoc-scipy.json") ~= nil end, 500)' -c qa || \
    note "docs download failed; in gv: :GvDocs install"
fi

# ── 6b. offline Wikipedia (physics + maths, Kiwix) ─────────────────────────────
if [[ $WIKI == 1 ]]; then
  say "Offline physics + maths Wikipedia (~650 MB)"
  "$G/nvim/bin/nvim" --headless -c 'lua require("gv.wiki").install(); vim.wait(3600000, function() return #vim.fn.glob(vim.fn.stdpath("data").."/wiki/*.part", false, true) == 0 and #vim.fn.glob(vim.fn.stdpath("data").."/wiki/*.zim", false, true) >= 2 end, 2000)' -c qa || \
    note "Wikipedia download failed; in gv: :GvWiki install"
fi

# ── 7. Claude Code (Space a a in gv) ───────────────────────────────────────────
if [[ $CLAUDE == 1 ]] && ! have claude && [[ ! -x $HOME/.local/bin/claude ]]; then
  say "Claude Code (the AI panel: Space a a)"
  if ask "Install Claude Code from claude.ai?"; then
    curl -fsSL https://claude.ai/install.sh | bash || note "Claude Code didn't install; later: curl -fsSL https://claude.ai/install.sh | bash"
    note "run  claude  once in a terminal to log in"
  fi
fi

# ── 8. Super+? opens the dictionary (GNOME) ────────────────────────────────────
if have gsettings && [[ ${XDG_CURRENT_DESKTOP:-} == *GNOME* ]]; then
  base=org.gnome.settings-daemon.plugins.media-keys
  path=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/gaussianvim-dict/
  list=$(gsettings get $base custom-keybindings 2>/dev/null || echo "[]")
  if [[ $list != *gaussianvim-dict* ]]; then
    if [[ $list == "@as []" || $list == "[]" ]]; then new="['$path']"; else new="${list%]}, '$path']"; fi
    gsettings set $base custom-keybindings "$new"
    gsettings set $base.custom-keybinding:$path name "GaussianVim Dictionary"
    gsettings set $base.custom-keybinding:$path command "$BIN/gv-dict"
    gsettings set $base.custom-keybinding:$path binding "<Super>question"
    note "Super+? opens the GaussianVim Dictionary"
  fi
fi

touch "$G/.installed"
say "Checking the install (gv-doctor)"
"$BIN/gv-doctor" || true

say "Done"
note "gv            GaussianVim (or the GaussianVim app)"
if [[ $VIMONLY == 0 ]]; then note "gtex          LaTeX projects (GaussianTeX app)"; fi
note "gv-dict       every key and alias (Super+?, Space ? in gv)"
note "gv-doctor     check the install        gv-theme   Material / Classic look"
note "The guide: $REPO/docs/GUIDE.md  (:GvGuide in gv)"
have claude || [[ -x $HOME/.local/bin/claude ]] || note "Claude panel needs Claude Code: curl -fsSL https://claude.ai/install.sh | bash"
