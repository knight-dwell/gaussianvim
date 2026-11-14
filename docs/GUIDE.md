# GaussianVim + GaussianTeX: the guide

GaussianVim (`gv`) is a light Vim-style editor for physics work: run code with
plots, live error checks, docs, Claude. GaussianTeX (`gtex`) is the same
editor set up for LaTeX: Overleaf-style projects, templates, live PDF, spell and
grammar checks, and short aliases for maths.

**Lost? Press `Space ?`** (or **Super+?** anywhere): the Dictionary app lists every
key and alias, searchable in plain words ("make a fraction", "stop the program").
Inside gv, `:GvGuide` opens this guide.

`Space` is the leader key: `Space r r` means press Space, then r, then r.
Press Space and wait to see a menu of everything under it.

---

## Contents

1. [Starting](#1-starting)
2. [Editing basics](#2-editing-basics)
3. [Running code (F5) and plots](#3-running-code-f5-and-plots)
4. [Docs, Stack Exchange, Claude](#4-docs-stack-exchange-claude)
5. [GaussianTeX: projects](#5-gaussiantex-projects)
6. [GaussianTeX: writing](#6-gaussiantex-writing)
7. [LaTeX aliases with examples](#7-latex-aliases-with-examples)
8. [Compiling and the PDF](#8-compiling-and-the-pdf)
9. [Installing on another computer (Ubuntu)](#9-installing-on-another-computer-ubuntu)
10. [Updating the repo](#10-updating-the-repo)
11. [Where things live](#11-where-things-live)
12. [The look: Material or Classic](#12-the-look-material-or-classic)

---

## 1. Starting

| Do this | To get |
|---|---|
| `gv` or `gv file.py` | GaussianVim (also "GaussianVim" in the app menu) |
| `gtex` | GaussianTeX: the LaTeX project menu (also the "GaussianTeX" app) |
| `gtex new` | straight to "choose a template" |
| `gv file.tex` | a .tex file opens in the GaussianTeX window (gv + the PDF); `GTEX_TERMINAL=1 gv file.tex` keeps it in the terminal |
| `gv-dict` / **Super+?** | the Dictionary of every key and alias |
| `vimhelp delete line` | the same, in the terminal |

On the start screen: `f` find a file, `r` recent files, `t` LaTeX projects,
`?` the Dictionary, `s` restore your last session.

### The window

`gtex` (and, in the Material look, the GaussianVim app) opens its own window:
gv on the left, the PDF on the right. In the **Material** look the title bar
holds the buttons as rounded pills (**▶ Compile**, **Files**, **Find**,
**Copy / Paste**, **Backup**, the PDF width **35% / 50% / 70%** and **Show PDF**)
and gv and the PDF sit in rounded cards. GaussianVim's window shows only Files,
Find, Copy and Paste until a PDF is open.

| Key | Does |
|---|---|
| `Ctrl+Shift+P` / `Space l h` | fold the PDF away / bring it back (also the PDF tab at the right edge) |
| `Ctrl+Shift+Left` / `Right` | PDF wider / narrower (or drag the divider; the width is remembered) |
| `Ctrl+Shift+C` / `Ctrl+Shift+V` | copy the selection / paste (`Shift+drag` selects anything on screen) |

## 2. Editing basics

Vim has modes. You start in **normal mode** (keys are commands); `i` goes to
**insert mode** (keys type text); `Esc` (or `jk`) comes back.

| Key | Does |
|---|---|
| `i` / `a` / `o` | insert before / after the cursor / on a new line below |
| `Esc` or `jk` | back to normal mode |
| `Space w` or `Ctrl+s` | save |
| `u` / `Ctrl+r` | undo / redo |
| `dd` / `yy` / `p` | delete (cut) / copy / paste a line |
| `/word` then `n` | search, next match |
| `:%s/old/new/g` | replace everywhere |
| `Space f` | find a file by name |
| `Space e` | the file tree on the left (Enter opens, `a` add, `r` rename, `d` delete) |
| `Space s t` | search text in the whole project |
| `Shift+h` / `Shift+l` | previous / next open file |
| `|` / `-` | split side by side / top-bottom; `Ctrl+h j k l` moves between splits |
| `Space /` | comment / uncomment |
| `gd` / `K` | go to definition / docs of the word under the cursor |
| `Space l a` / `gl` | quick fix / full message for the error on this line |
| `Space g m` | git menu (commit, push, pull, branches); `Space G` the Source Control card |
| `Ctrl+\` | floating terminal (again to hide); `Esc Esc` inside it to scroll |

**Floating panels** (Claude, docs, Wikipedia, answers, terminals) can be moved
and resized: drag the title bar or the edges, or `Alt+arrows` (move),
`Alt+Shift+arrows` (size), `Alt+=` / `Alt+-` (bigger / smaller), `Alt+m` (fill
the screen). **`Ctrl+q`** hides a panel to the **dock** (bottom right of the
status line); click it there, `Ctrl+q` in the editor, or `Space u h` brings it
back where it was. Selecting text in a panel with the mouse copies it.

## 3. Running code (F5) and plots

**F5** runs the file you're editing (Python, C, C++, Fortran, Julia, Bash, Lua).
A card opens on the right:

- **Output** (top): what the program prints. `Space r o` lets you type into it (`input()`).
- **Results** (middle): errors you can jump to (Enter), the **plots** and the **files** the run wrote.
- **Viewer** (bottom): the plot or file picked in Results.

| Key | Does |
|---|---|
| `F5` | run (saves first) |
| `Ctrl+C` / `Ctrl+Z` / `Shift+F5` | stop. First like Ctrl+C in a terminal (Python shows the line it was on), killed if it is still going 2 s later |
| `Space r ]` / `Space r [` | next / previous plot or file, from the editor |
| `j` `k` or a click in Results | show that plot / file in the viewer |
| mouse wheel, `+` `-` | zoom the plot inside the card; drag or `hjkl` move; `0` fit |
| `w` | the plot as a real matplotlib window (toolbar, save) |
| `Enter` on a csv / dat / txt | the whole file in the editor (the viewer shows it as a table) |
| `o` | open the plot / file with its normal app |
| `a` | ask Claude why the run failed |
| `q` / `Q` | hide the card to a small pill / close it |
| `Space r i` | Python console with your file run first (inspect variables) |

**Example.** A script that makes three figures and saves `data.csv`: press F5,
the card lists *Plot 1, Plot 2, Plot 3* and *data.csv*. `Space r ]` steps through
them; on a plot, scroll to zoom into a peak; on `data.csv` you see the columns
lined up.

## 4. Docs, Stack Exchange, Claude

### Offline docs

`Space s d` searches NumPy, SciPy, Matplotlib, Python, pandas, LaTeX, Fortran and
Bash documentation, offline. Type `linspace`, `quad`, `savefig`, `fft`; the
right side previews the page; Enter opens it.

- **Enter on a module** (`scipy.integrate`, `numpy.linalg`, `matplotlib.pyplot`)
  opens it as a **tree**: its sub-modules (folders) and functions with one-line
  summaries. Enter goes in, `..` goes up, the first line reads the module page.
- Pages are formatted: the signature in a code block, Parameters / Returns /
  Examples sections, examples as Python code, maths typeset.
- In a page `q` goes back to the list where you were, `Q` closes. `Space s D` looks up
the word under the cursor. `:GvDocs install julia sympy` adds more sets
(names from devdocs.io); SciPy comes from your installed SciPy (like `help()`).

### Stack Exchange

`Space s x`: pick a site (Stack Overflow, TeX, Physics, Mathematics, Unix, Ask
Ubuntu), the search box starts with the error on your line (or your selection).
Up to 100 results show at once; the last line, **Load more results…**, fetches
the next 100. Enter reads the question with its best answers inside gv, with the maths
typeset (Physics and Mathematics); `q` goes back to the results, `Q` closes,
`o` opens it in the browser, `p` the rendered Reader (below).

### Wikipedia

`Space s w` searches Wikipedia (the word under the cursor, or your selection).
Online results come from en.wikipedia.org; the **offline physics and maths
Wikipedia** (Kiwix, ~650 MB, `:GvWiki install`) answers too, and alone when
there is no internet. Articles open with the maths typeset: **Enter** on a link
opens that article, **t** lists the sections to jump to, **q** goes back,
**o** opens it in the browser, **p** the rendered Reader.

### The Reader: equations and figures (Material look)

gv can draw equations and pictures only in **kitty**. Everywhere else (the
GaussianTeX / GaussianVim window, gnome-terminal) a Wikipedia article or a
Stack Exchange question also opens in the **Reader**: a window with the
equations typeset and the figures shown, in gv's colours. In kitty press `p`
in the text reader to open it.

- Links to other Wikipedia articles open in the Reader; other links in the browser.
- `Backspace` / `Alt+Left` back, `Alt+Right` forward, `j` `k` scroll,
  `Ctrl +` / `Ctrl -` / `Ctrl 0` zoom, `o` the browser, `q` / `Esc` close.
- Offline Wikipedia has equations but no pictures (the Kiwix files are the
  "nopic" edition); online articles have both. Stack Exchange maths needs the
  internet (MathJax).

### Claude

Claude Code runs in a panel on the right, in your project folder. It can read
and (when you allow it) edit your files; gv reloads files it changes.

| Key | Claude does |
|---|---|
| `Space a a` | show / hide the panel (`Ctrl+q` inside hides it) |
| `Space a e` | explains and fixes the error on this line |
| `Space a s` (visual) | gets your selection; you type the question |
| `Space a f` | reviews the file: bugs, logic, numerics (in .tex: physics, maths, notation) |
| `Space a r` (or `a` in the run card) | finds why the last F5 run failed |
| `Space a l` | fixes the LaTeX compile errors |
| `Space a w` | checks the paragraph: wording, grammar, physics logic |

The first time in a folder Claude asks whether you trust it: press Enter, then
use the key again. Claude Code must be installed and logged in once
(`claude` in a terminal).

### Maths in Markdown

In any Markdown file (`.md` notes, the docs and Stack Exchange readers),
`$...$` and `$$...$$` are drawn as typeset equations in kitty (only there:
other terminals show the LaTeX source), and so are
`![](picture.png)` links. Move the cursor onto an equation to edit its source.
`.tex` files are never drawn over: there you see your LaTeX.

## 5. GaussianTeX: projects

`gtex`, the GaussianTeX app, `Space t` in gv or `t` on the start screen:

- **New project from a template**: pick one (a preview shows its main file),
  type a name. You get `~/GaussianTeX/<name>/` ready to compile.
- **Open a project**: newest first, with a preview.
- **Import a .zip**: from Overleaf ("Download source"), arXiv or a colleague.
- **Rename a project**: renames the folder (open files are saved and reopened).

| Template | What you get |
|---|---|
| Thesis (JNCASR; on your laptop only, not in the public repo) | book + `jncthesis.sty`: title page with the logo, declaration, certificate, acknowledgements, publications, synopsis, chapters (each with references), appendix. Your details: `Formal/formal.tex` |
| Physical Review B | REVTeX 4.2, two-column reprint style, APS references |
| arXiv preprint | one-column article, authors with affiliations, natbib |
| Nature letter | the nature class: summary paragraph, main text, Methods, addendum |
| Maths / physics notes | contents, numbered theorem / lemma / definition / example, proofs |
| Book | front matter, chapters in their own files, appendix, bibliography |
| Talk slides | Beamer 16:9 |
| Blank article | the minimum |

Add your own: copy a folder in `~/.config/gaussianvim/tex-templates/`, edit its
files and `template.json`. `{{TITLE}}`, `{{AUTHOR}}`, `{{DATE}}` are filled in.

In a project: **`Space e`** (or the **Files** button) shows its files on the
left; **`U`** uploads files into the folder under the cursor (a file chooser
opens in Downloads); `P` previews figures. **`Space l z`** exports the project
as `~/Downloads/<name>.zip` without build files, for Overleaf, a journal or a
colleague.

### Backups

**`Space l B`** (or the **Backup** button) is the backup menu:

- **Back up now**: a .zip of the project (sources, figures, the PDF; no build
  files) in `~/GaussianTeX-backups/<project>/`.
- **Auto backup**: on save, at most every 10 minutes; the newest 30 are kept.
- **Restore…**: newest first; unpack into a new folder next to the project
  (safe) or over the project (the current state is backed up first).
- **Previous version of this file**: every file keeps its last version on save.
- **gv config**: snapshots of `~/.config/gaussianvim` (daily, 15 kept) and its
  git history; any change can be undone.

### Sharing with other gv users (like Overleaf's Share)

**`Space l o`** (or the **Share** button) shares the project through a
**private** GitHub repository: only the people you invite can see it. You need
a free GitHub account and the GitHub CLI `gh` (the menu offers the one-time
login; it opens your browser).

- **Share on GitHub…**: shows what will be uploaded (build files such as `.aux`
  `.log` `.bbl` and the compiled PDF stay out: everyone compiles their own) and
  warns about files GitHub won't take (over 100 MB). Then it asks whom to invite.
- **Invite someone…**: their GitHub username, or the email of their GitHub
  account. GitHub emails them the invitation; a short "how to open it" message
  is copied for you to paste into a mail or chat.
- **Sync** (`Space l o`, then `s`): saves, takes the others' changes, sends
  yours, and says who changed which files. Open files reload by themselves.
  If you both changed the same lines, a card opens the marked spot
  (`<<<<<<<` yours, `=======`, theirs `>>>>>>>`): keep the right text, delete
  the marker lines, save, Sync again. Or pick *Keep my version* / *Take their
  version* for the whole file.
- **People with access…**: remove someone, or cancel an invitation.
- Opening a shared project checks in the background (at most every 5 minutes)
  and tells you when someone else changed it.

On the other computer (yours at the lab, or your colleague's):
**`gtex` → Open a shared project** (`Space t`, then `s`) lists your invitations
(accept and open in one go), projects shared with you, and your own shared
projects; they download into `~/GaussianTeX/`.

It's not live typing: you each edit, then Sync, like taking turns. Live
co-editing (Teamtype) may come later; the JNCASR network blocks the services it
needs today.

## 6. GaussianTeX: writing

- **Spelling**: wrong words get a red wavy underline as you type (not maths,
  labels or comments). `z=` suggestions, `]s` next one, `zg` adds a word.
- **Grammar** (LanguageTool): a few seconds after you stop typing, mistakes are
  underlined; rest the cursor on one and the fix shows below it
  (`could of → could have`); `z=` picks it. `Space u g` turns it off (it uses
  ~700 MB while on).
- **Rephrase** with your local Qwen: `Space l p` on a paragraph (or a
  selection). Enter puts the new version in (`u` undoes it); `s` shorter, `g`
  grammar only, `f` more formal, `r` again. (Needs the `qwen-server` setup in
  `~/local-llm`; on other machines use Claude: `Space a w`.)
- **Command menu** like Overleaf: type `\sec`, `\begin{`, `\ref{`, `\cite{`,
  `\includegraphics{`: commands, environments, your labels, your bib keys,
  your figures. Tab / Ctrl+j move, Enter takes it.
- Picking an environment after `\begin{` writes **the whole block**:
  `\begin{figure}` gives `\centering`, `\includegraphics`, `\caption`, `\label`.
- Cursor on an `\includegraphics{...}` line: **the figure pops up** under it.

## 7. LaTeX aliases with examples

There are two kinds. Both write plain standard LaTeX (amsmath at most), so the
file compiles anywhere, Overleaf included.

### 7a. Menu aliases: type, Tab, Enter

In insert mode type the alias, **Tab** selects it in the menu, **Enter** writes
it. The first blank is highlighted: type over it, **Tab** jumps to the next.

**Example: an integral.**

```
you type:   intgrl  Tab Enter  0  Tab  \infty  Tab  e^{-x^2}  Tab  x  Tab
you get:    \int_{0}^{\infty} e^{-x^2} \, \mathrm{d}x
```

**Example: a partial derivative.**

```
you type:   pdv  Tab Enter  \psi  Tab  t  Tab
you get:    \frac{\partial \psi}{\partial t}
```

**Example: a figure.**

```
you type:   figure  Tab Enter  0.7  Tab  phase_diagram  Tab  The phase diagram.  Tab  phase  Tab
you get:    \begin{figure}[htbp]
              \centering
              \includegraphics[width=0.7\linewidth]{phase_diagram}
              \caption{The phase diagram.}
              \label{fig:phase}
            \end{figure}
```

| Alias | Writes |
|---|---|
| `figure` `fig` | a whole figure (centred, width, caption, label) |
| `table` `tab` | a table with caption, label and a 3-column tabular with lines |
| `tabular` | a tabular on its own |
| `equation` `eq` / `eql` | a numbered equation / with a label |
| `align` `ali` | equations lined up at `=` |
| `itemize` `item` / `enumerate` `enum` | bullet / numbered list |
| `matrix` `pmatrix` / `bmatrix` / `det` | 2×2 matrix in ( ) / [ ] / determinant |
| `cases` | a piecewise definition |
| `frac` | `\frac{}{}` |
| `intgrl` `int` / `intinf` / `iint` | ∫ₐᵇ f(x) dx / over all x / double integral |
| `sum` / `prod` / `lim` | with limits |
| `pdv` / `pdv2` / `pdvm` | ∂f/∂x, ∂²f/∂x², ∂²f/∂x∂y |
| `dv` / `dv2` | df/dx, d²f/dx² |
| `dot` / `ddot` | ẋ, ẍ |
| `grad` `divg` `curl` `lap` | ∇f, ∇·A, ∇×A, ∇²f |
| `bra` `ket` `braket` `avg` | ⟨ψ\|, \|ψ⟩, ⟨φ\|ψ⟩, ⟨A⟩ |
| `abs` `norm` `vec` `bvec` `hat` | \|x\|, ‖x‖, arrow, bold, operator hat |
| `sqrt` `sci` | √x, 1.0×10³ |
| `im` / `dm` | `$...$` / `\[ ... \]` |
| `sec` `sub` `subsub` | sections |

### 7b. Instant maths aliases: just type

Inside maths (`$…$`, equation, align) these turn into LaTeX **the moment you
type them**: no menu, no Tab. They never fire in normal text, and not inside an
index (`\sigma_{xx}`, `t_{pd}` stay as typed). `Space u a` turns them off.

**Example.**

```
you type:   $E = mcsr$
you get:    $E = mc^2$

you type:   $//a Tab b Tab + ;a oo$
you get:    $\frac{a}{b} + \alpha \infty$

you type:   $\int_0^oo eeikx Tab dd x$
you get:    $\int_0^\infty e^{ikx} \mathrm{d} x$

you type:   $xtdn+1 Tab$
you get:    $x^{n+1}$
```

| Type | Get | | Type | Get |
|---|---|---|---|---|
| `//` | `\frac{}{}` | | `oo` | `\infty` |
| `sr` / `cb` | `^2` / `^3` | | `xx` / `**` | `\times` / `\cdot` |
| `td` | `^{}` | | `->` `=>` | `\to` `\implies` |
| `inv` | `^{-1}` | | `<=` `>=` `!=` `~~` | `\leq \geq \neq \approx` |
| `__` | `_{}` | | `+-` / `...` | `\pm` / `\dots` |
| `sq` | `\sqrt{}` | | `pd` `nb` `hb` | `\partial \nabla \hbar` |
| `ee` | `e^{}` | | `dd` | `\mathrm{d}` |
| `bf` / `rm` | `\mathbf{}` / `\mathrm{}` | | `lr(` `lr[` `lr\|` | growing brackets |

**Greek**: `;` + letter. `;a` α, `;b` β, `;g` γ, `;G` Γ, `;d` δ, `;D` Δ, `;e` ε,
`;ve` ε (varepsilon), `;z` ζ, `;h` η, `;q` θ, `;Q` Θ, `;k` κ, `;l` λ, `;L` Λ,
`;m` μ, `;n` ν, `;x` ξ, `;p` π, `;P` Π, `;r` ρ, `;s` σ, `;S` Σ, `;t` τ, `;f` φ,
`;vf` φ (varphi), `;F` Φ, `;c` χ, `;y` ψ, `;Y` Ψ, `;w` ω, `;W` Ω.

Your own aliases: `~/.config/gaussianvim/snippets/tex.json` (menu) and
`~/.config/gaussianvim/tex-auto.json` (instant). New ones appear in the
Dictionary by themselves.

## 8. Compiling and the PDF

| Do this | Get |
|---|---|
| `F5` or the **▶ Compile** button (top right) | compiles with latexmk; then it **compiles again on every save** |
| the button turns **✗ 2 errors** | click it (or `Space l e`) for the list; the lines get red marks |
| **PDF** button / `Space l v` | the PDF beside gv (zathura), at the spot of your cursor |
| `Ctrl+click` in the PDF | jumps to that line in gv |
| `Shift+F5` | stop compiling on save |
| `Space a l` | Claude fixes the compile errors |

**Faster compiles** (measured on a 116-page thesis: 15 s → 3.4 s per save, ~1–3 s in fast mode):

- Big pictures (50-megapixel PNGs) are what makes LaTeX slow. GaussianTeX keeps
  print-resolution copies (4000 px ≈ 600 dpi on A4) in a hidden `.gvfast/`
  folder and LaTeX uses them; your figure files are never changed.
  **`Space l Q`** makes a full-quality PDF from the originals (for the final version).
- **⚡ Fast** (button, or `Space l F`) in a chapter file: only that chapter (and the
  front matter) is typeset; page numbers and references to other chapters stay.
  Press again for the whole document.
- "⚠ Compiled with warnings" means the PDF is there but e.g. BibTeX complained
  (duplicate entries): click it for the list.

## 9. Installing on another computer

Works on a fresh Linux (Ubuntu / Debian / Mint, Fedora, Arch / Manjaro, openSUSE;
x86_64 or arm64); the installer brings every dependency itself. One line, from
nothing (it installs git, downloads the repo to `~/gaussianvim`, runs the installer):

```bash
curl -fsSL https://raw.githubusercontent.com/knight-dwell/gaussianvim/main/get.sh | bash
```

Only the editor (GaussianVim, no LaTeX, ~1 GB less):

```bash
curl -fsSL https://raw.githubusercontent.com/knight-dwell/gaussianvim/main/get.sh | bash -s -- --vim-only
```

Or from a clone: `./install.sh` (everything) or `./install-gv.sh` (GaussianVim only).

| It installs | |
|---|---|
| system packages | git, ripgrep, fd, compilers (gcc, gfortran), Python with NumPy / SciPy / Matplotlib, GTK + VTE + WebKit (the window and the Reader), pandoc, poppler, kitty, clipboard tools; with LaTeX: TeX Live (revtex, nature, …), latexmk, zathura. Names a release doesn't have are skipped, not fatal |
| its own Neovim 0.12 | in `~/.local/share/gaussianvim`, never touching a Vim / Neovim you have |
| its own Node 22 | only when the system Node is missing or older than 18 (Ubuntu 22.04 ships 12) |
| the rest | a Nerd Font, plugins, language servers, offline docs, offline Wikipedia (not with `--vim-only`), Claude Code (asks), Super+? for the Dictionary on GNOME |

Options: `--vim-only`, `--theme classic` (start with the Classic look), `--no-tex`,
`--no-docs`, `--no-wiki`, `--no-claude`, `--no-system` (no sudo: only GaussianVim
itself), `--yes` (ask nothing). Run it again to update: your config changes are
committed to its git history first, and the look you use is kept.

Afterwards **`gv-doctor`** lists every part as ✓ / ✗ / ○ (optional) with what it
is for; run the installer again for anything missing. Open a new terminal, then:
`gv`, `gtex`, `gv-dict`. Plots inside the run card and equations in Markdown need
the **kitty** terminal; the window and the Reader need a desktop (X11, or Wayland
through XWayland).

## 10. Updating the repo

After changing things on your laptop:

```bash
cd ~/gaussianvim
./sync.sh                         # copies the live files into the repo (both looks; run it in the Material look)
git add -A && git commit -m "what changed" && git push
```

On the lab computer: `git pull && ./install.sh`.

## 11. Where things live

| Path | What |
|---|---|
| `~/.config/gaussianvim/` | the config: `lua/gv/*.lua`, `cheatsheet.tsv` (Dictionary entries), `snippets/tex.json`, `tex-auto.json`, `tex-templates/` |
| `~/.local/share/gaussianvim/` | Neovim itself, plugins, language servers, `docs/`, the Dictionary app |
| `~/.local/bin/` | `gv`, `gtex`, `gv-dict`, `vimhelp`, `gv-theme`, `gv-doctor` |
| `~/.config/gaussianvim/runner/` | the windows: `gvwindow.py` (GaussianTeX / GaussianVim), `gvreader.py` (the Reader), `gvtheme.py` (their colours) |
| `~/GaussianTeX-backups/` | project backups and gv config snapshots |
| `~/GaussianTeX/` | your LaTeX projects |
| `~/gaussianvim/` | the repo (`install.sh`, `install-gv.sh`, `get.sh`, `sync.sh`) |

## 12. The look: Material or Classic

GaussianVim has two looks, kept apart as two git branches of the config
(`material` and `classic` in `~/.config/gaussianvim`):

| | Material | Classic |
|---|---|---|
| title bar | dark, with the buttons as rounded pills | the desktop's title bar, a toolbar below it |
| editor / PDF | rounded cards | edge to edge |
| file tree (`Space e`) | a rounded card: folders in the accent colour, git state in colour, rounded branches | plain sidebar |
| top of each file | the file name as a chip with its icon | the file name |
| Wikipedia / Stack Exchange | equations and figures in the Reader | equations only in kitty |
| GaussianVim app | opens in the window | opens in kitty |

**Switch**: `Space u T` (or `:GvTheme material` / `:GvTheme classic`) inside gv;
gv saves everything and offers to restart on the same file. From a terminal:
`gv-theme material`, `gv-theme classic`, or `gv-theme` to see which is active
(it also sets the app-menu launchers). Changes you make to the config are saved
on the branch you're on; settings both looks share (keys, aliases) have to be
added to both branches.

