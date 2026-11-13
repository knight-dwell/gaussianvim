# GaussianVim + GaussianTeX

A light Vim-style editor for physics work (`gv`), and the same editor set up as an
Overleaf-like LaTeX app (`gtex`). Built on Neovim 0.12; installs next to any Vim /
Neovim you already have without touching them.

- **Run code with F5**: output, errors you can jump to, matplotlib plots and data
  files right inside a card (zoom, step through them), stop with Ctrl+C.
- **LaTeX like Overleaf**: projects from templates (JNCASR thesis, Physical Review B,
  arXiv, Nature, notes, book, Beamer), Compile / PDF buttons, compile on save,
  zathura beside the editor with SyncTeX, spell + grammar checks, the command menu,
  full environment templates, short maths aliases (`//` → `\frac{}{}`, `;a` → `\alpha`),
  figure previews, project files with upload, zip export.
- **Help built in**: offline NumPy / SciPy / Matplotlib / Python / pandas / LaTeX docs,
  Stack Exchange search, Claude Code in a side panel, and a searchable Dictionary of
  every key and alias (Super+?).

## Install (Ubuntu, Debian, Fedora, Arch)

```bash
gh repo clone knight-dwell/gaussianvim ~/gaussianvim   # private repo: gh auth login first
cd ~/gaussianvim && ./install.sh                       # --help for options
```

Then: `gv`, `gtex`, `gv-dict`. **Read [docs/GUIDE.md](docs/GUIDE.md)** (also `:GvGuide`
inside gv): every key, every template, every alias with examples.

## Layout

| In the repo | Installed to |
|---|---|
| `config/` | `~/.config/gaussianvim/` |
| `share/dictionary/`, `share/brand/` | `~/.local/share/gaussianvim/` |
| `bin/` (`gv`, `gtex`, `gv-dict`, `vimhelp`) | `~/.local/bin/` |
| `applications/` | `~/.local/share/applications/` |

`./sync.sh` copies the live files of this machine back into the repo before a commit.

KaTeX (in `share/dictionary/web/katex`) is MIT licensed. `config/tex-templates/thesis-jncasr`
carries JNCASR's `jncthesis.sty` and logo for the thesis template.
