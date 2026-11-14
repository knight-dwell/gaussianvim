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

---

## 1. Starting

| Do this | To get |
|---|---|
| `gv` or `gv file.py` | GaussianVim (also "GaussianVim" in the app menu) |
| `gtex` | GaussianTeX: the LaTeX project menu (also the "GaussianTeX" app) |
| `gtex new` | straight to "choose a template" |
| `gv-dict` / **Super+?** | the Dictionary of every key and alias |
| `vimhelp delete line` | the same, in the terminal |

On the start screen: `f` find a file, `r` recent files, `t` LaTeX projects,
`?` the Dictionary, `s` restore your last session.

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
`o` opens it in the browser.

### Wikipedia

`Space s w` searches Wikipedia (the word under the cursor, or your selection).
Online results come from en.wikipedia.org; the **offline physics and maths
Wikipedia** (Kiwix, ~650 MB, `:GvWiki install`) answers too, and alone when
there is no internet. Articles open with the maths typeset: **Enter** on a link
opens that article, **t** lists the sections to jump to, **q** goes back,
**o** opens it in the browser.

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
`$...$` and `$$...$$` are drawn as typeset equations in kitty, and so are
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

## 9. Installing on another computer (Ubuntu)

The repo is public (github.com/knight-dwell/gaussianvim). On any computer:

```bash
sudo apt install -y git
git clone https://github.com/knight-dwell/gaussianvim ~/gaussianvim
cd ~/gaussianvim && ./install.sh
```

`install.sh` installs everything (Neovim 0.12, TeX Live for the templates,
zathura, Python with NumPy/SciPy/Matplotlib, kitty, a Nerd Font, the language
servers, the offline docs, and offers Claude Code), copies GaussianVim and
GaussianTeX, adds the app-menu entries and, on GNOME, Super+? for the
Dictionary. Options: `--no-tex` (skip TeX Live), `--no-docs`, `--no-claude`,
`--no-system` (no sudo: only GaussianVim itself), `--yes` (ask nothing).
It also works on Fedora (dnf) and Arch (pacman). Run it again to update.

Then open a new terminal: `gv`, `gtex`, `gv-dict`. Plots inside the run card
need the **kitty** terminal (the installer gives it the font).


## 10. Updating the repo

After changing things on your laptop:

```bash
cd ~/Projects/gaussianvim
./sync.sh                         # copies the live files into the repo
git add -A && git commit -m "what changed" && git push
```

On the lab computer: `git pull && ./install.sh`.

## 11. Where things live

| Path | What |
|---|---|
| `~/.config/gaussianvim/` | the config: `lua/gv/*.lua`, `cheatsheet.tsv` (Dictionary entries), `snippets/tex.json`, `tex-auto.json`, `tex-templates/` |
| `~/.local/share/gaussianvim/` | Neovim itself, plugins, language servers, `docs/`, the Dictionary app |
| `~/.local/bin/` | `gv`, `gtex`, `gv-dict`, `vimhelp` |
| `~/GaussianTeX/` | your LaTeX projects |
| `~/Projects/gaussianvim/` | this repo |
