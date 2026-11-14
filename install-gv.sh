#!/usr/bin/env bash
# GaussianVim only: the editor with everything it needs (its own Neovim, Node when
# the system one is too old, Python with NumPy / SciPy / Matplotlib, compilers,
# language servers, a Nerd Font, the offline docs, the window and the Reader),
# without TeX Live and the offline Wikipedia. Assumes nothing is installed.
#
#   ./install-gv.sh              (options as for install.sh: --yes, --no-docs, --theme classic, ...)
#   curl -fsSL https://raw.githubusercontent.com/knight-dwell/gaussianvim/main/get.sh | bash -s -- --vim-only
#
# LaTeX later: ./install.sh (adds GaussianTeX; nothing is lost).
exec "$(cd "$(dirname "$0")" && pwd)/install.sh" --vim-only "$@"
