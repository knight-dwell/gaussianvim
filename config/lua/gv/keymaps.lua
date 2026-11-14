-- Keys: the same as LunarVim's defaults (plus your own | and - splits), so `vim`
-- and `gv` behave alike. Space is the leader: press it and wait for the menu.
-- Keys that need a language server (gd, gl, Space l ...) are in lsp.lua,
-- debugger keys (Space d ...) in plugins/lvim.lua.
local map = function(mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true }) end
local gs = function(fn, ...)
  local a = { ... }
  return function()
    local f = require("gitsigns")[fn]
    if f then f(unpack(a)) else vim.notify("gitsigns has no " .. fn .. " (press Space gs again to unstage)") end
  end
end

-- project root: the folder with .git (or pyproject.toml, ...) above the file, as LunarVim's project.nvim
local function root() return vim.fs.root(0, { ".git", "pyproject.toml", "setup.py", "Makefile", "latexmkrc", ".latexmkrc" }) or vim.uv.cwd() end

-- top level (LunarVim: Space ; w q / c f h e)
map("n", "<leader>;", function() Snacks.dashboard() end, "Dashboard")
map("n", "<leader>w", "<cmd>w!<cr>", "Save")
map("n", "<leader>q", "<cmd>confirm q<cr>", "Quit")
vim.keymap.set("n", "<leader>/", "gcc", { remap = true, desc = "Comment line" })
vim.keymap.set("v", "<leader>/", "gc", { remap = true, desc = "Comment selection" })
map("n", "<leader>c", function() Snacks.bufdelete() end, "Close buffer")
map("n", "<leader>f", function() Snacks.picker.files({ cwd = root() }) end, "Find file")
map("n", "<leader>h", "<cmd>nohlsearch<cr>", "No highlight")
map("n", "<leader>e", function() Snacks.explorer({ cwd = root() }) end, "Explorer")
-- the GaussianVim Dictionary app (Super+? anywhere); without a display, the list inside gv
map("n", "<leader>?", function()
  local app = vim.fn.expand("~/.local/bin/gv-dict")
  if (vim.env.DISPLAY or vim.env.WAYLAND_DISPLAY) and vim.fn.executable(app) == 1 then
    vim.system({ app }, { detach = true })
  else
    require("gv.cheatsheet").open()
  end
end, "Dictionary: every key and LaTeX alias")
map("n", "<leader>P", function() Snacks.picker.projects() end, "Projects")
-- offline docs, Stack Exchange, Claude
map("n", "<leader>sd", function() require("gv.docs").search() end, "Docs: NumPy, SciPy, Matplotlib, Python, …")
map("n", "<leader>sD", function() require("gv.docs").search(vim.fn.expand("<cword>")) end, "Docs for the word under the cursor")
map("n", "<leader>sx", function() require("gv.stackex").search(false) end, "Stack Exchange (SO, TeX, Physics, Math)")
map("n", "<leader>sw", function() require("gv.wiki").search(false) end, "Wikipedia (online + offline physics / maths)")
vim.keymap.set("x", "<leader>sw", function() vim.cmd("normal! \27"); require("gv.wiki").search(true) end, { desc = "Wikipedia: the selection" })
vim.keymap.set("x", "<leader>sx", function() vim.cmd("normal! \27"); require("gv.stackex").search(true) end, { desc = "Stack Exchange: the selection" })
map("n", "<leader>aa", function() require("gv.claude").toggle() end, "Claude panel (show / hide)")
map("n", "<leader>ae", function() require("gv.claude").error_here() end, "Claude: explain + fix the error on this line")
map("n", "<leader>af", function() require("gv.claude").review_file() end, "Claude: review this file (bugs, logic, physics)")
map("n", "<leader>ar", function() require("gv.claude").run_failed() end, "Claude: why did the run (F5) fail")
map("n", "<leader>al", function() require("gv.claude").latex_errors() end, "Claude: fix the LaTeX compile errors")
map("n", "<leader>aw", function() require("gv.claude").paragraph() end, "Claude: check this paragraph (wording, physics)")
vim.keymap.set("x", "<leader>as", function() vim.cmd("normal! \27"); require("gv.claude").selection() end, { desc = "Claude: send the selection" })
vim.api.nvim_create_user_command("GvGuide", function()
  local f = vim.fn.stdpath("data") .. "/GUIDE.md"
  if vim.fn.filereadable(f) == 0 then f = vim.fn.expand("~/Projects/gaussianvim/docs/GUIDE.md") end
  vim.cmd("tabedit " .. vim.fn.fnameescape(f))
  vim.bo.readonly = true
end, { desc = "the GaussianVim + GaussianTeX guide" })
map("n", "<leader>t", function() require("gv.texproject").start() end, "LaTeX projects: new from a template, open, import .zip, rename")
map("n", "<leader>G", function() require("gv.scm").toggle() end, "Source control (card)")
map("n", "<leader>gm", function() require("gv.gitmenu").open() end, "Git menu (dropdown)")

-- right-click menu: a few entries next to Neovim's own (Copy, Paste, ...)
vim.cmd([[
  amenu PopUp.-gv- <Nop>
  amenu PopUp.Git\ menu <cmd>lua require("gv.gitmenu").open("cursor")<cr>
  amenu PopUp.Source\ control <cmd>lua require("gv.scm").open()<cr>
  amenu PopUp.Who\ wrote\ this\ line <cmd>lua require("gitsigns").blame_line({ full = true })<cr>
  amenu PopUp.File\ tree <cmd>lua Snacks.explorer()<cr>
  amenu PopUp.Cheat\ sheet <cmd>lua require("gv.cheatsheet").open()<cr>
]])

-- Space b: buffers
map("n", "<leader>bj", "<cmd>BufferLinePick<cr>", "Jump")
map("n", "<leader>bf", function() Snacks.picker.buffers() end, "Find")
map("n", "<leader>bb", "<cmd>BufferLineCyclePrev<cr>", "Previous")
map("n", "<leader>bn", "<cmd>BufferLineCycleNext<cr>", "Next")
map("n", "<leader>bW", "<cmd>noautocmd w<cr>", "Save without formatting")
map("n", "<leader>be", "<cmd>BufferLinePickClose<cr>", "Pick which buffer to close")
map("n", "<leader>bh", "<cmd>BufferLineCloseLeft<cr>", "Close all to the left")
map("n", "<leader>bl", "<cmd>BufferLineCloseRight<cr>", "Close all to the right")
map("n", "<leader>bD", "<cmd>BufferLineSortByDirectory<cr>", "Sort by directory")
map("n", "<leader>bL", "<cmd>BufferLineSortByExtension<cr>", "Sort by language")
map("n", "<S-l>", "<cmd>BufferLineCycleNext<cr>", "Next buffer")
map("n", "<S-h>", "<cmd>BufferLineCyclePrev<cr>", "Previous buffer")

-- Space g: git
map("n", "<leader>gg", function()
  if vim.fn.executable("lazygit") == 1 then Snacks.lazygit() else vim.notify("lazygit is not installed", vim.log.levels.WARN) end
end, "Lazygit")
map("n", "<leader>gj", gs("nav_hunk", "next"), "Next hunk")
map("n", "<leader>gk", gs("nav_hunk", "prev"), "Previous hunk")
map("n", "<leader>gl", gs("blame_line"), "Blame")
map("n", "<leader>gL", gs("blame_line", { full = true }), "Blame line (full)")
map("n", "<leader>gp", gs("preview_hunk"), "Preview hunk")
map("n", "<leader>gr", gs("reset_hunk"), "Reset hunk")
map("n", "<leader>gR", gs("reset_buffer"), "Reset buffer")
map("n", "<leader>gs", gs("stage_hunk"), "Stage hunk")
map("n", "<leader>gu", gs("undo_stage_hunk"), "Undo stage hunk")
map("n", "<leader>go", function() Snacks.picker.git_status() end, "Open changed file")
map("n", "<leader>gb", function() Snacks.picker.git_branches() end, "Checkout branch")
map("n", "<leader>gc", function() Snacks.picker.git_log() end, "Commits")
map("n", "<leader>gC", function() Snacks.picker.git_log_file() end, "Commits (this file)")
map("n", "<leader>gd", gs("diffthis", "HEAD"), "Git diff")

-- Space p: plugins
map("n", "<leader>pi", "<cmd>Lazy install<cr>", "Install")
map("n", "<leader>ps", "<cmd>Lazy sync<cr>", "Sync")
map("n", "<leader>pS", "<cmd>Lazy home<cr>", "Status")
map("n", "<leader>pc", "<cmd>Lazy clean<cr>", "Clean")
map("n", "<leader>pu", "<cmd>Lazy update<cr>", "Update")
map("n", "<leader>pp", "<cmd>Lazy profile<cr>", "Profile")
map("n", "<leader>pl", "<cmd>Lazy log<cr>", "Log")
map("n", "<leader>pd", "<cmd>Lazy debug<cr>", "Debug")

-- Space s: search
-- colorscheme plugins load only when needed; load them all so the list shows every scheme
local function colorschemes()
  local names = {}
  for _, p in ipairs(require("lazy").plugins()) do
    if not p._.loaded and vim.uv.fs_stat(p.dir .. "/colors") then names[#names + 1] = p.name end
  end
  if #names > 0 then require("lazy").load({ plugins = names }) end
  Snacks.picker.colorschemes()
end
map("n", "<leader>sb", function() Snacks.picker.git_branches() end, "Checkout branch")
map("n", "<leader>sc", colorschemes, "Colorscheme")
map("n", "<leader>sp", colorschemes, "Colorscheme with preview")
map("n", "<leader>sf", function() Snacks.picker.files() end, "Find file")
map("n", "<leader>sh", function() Snacks.picker.help() end, "Find help")
map("n", "<leader>sH", function() Snacks.picker.highlights() end, "Find highlight groups")
map("n", "<leader>sM", function() Snacks.picker.man() end, "Man pages")
map("n", "<leader>sr", function() Snacks.picker.recent() end, "Open recent file")
map("n", "<leader>sR", function() Snacks.picker.registers() end, "Registers")
map("n", "<leader>sk", function() Snacks.picker.keymaps() end, "Keymaps")
map("n", "<leader>sC", function() Snacks.picker.commands() end, "Commands")
map("n", "<leader>sl", function() Snacks.picker.resume() end, "Resume last search")
map("n", "<leader>st", function() Snacks.picker.grep({ cwd = root() }) end, "Text")

-- Space T: tree-sitter
map("n", "<leader>Ti", "<cmd>checkhealth nvim-treesitter<cr>", "Info")
map("n", "<leader>Tp", function() vim.treesitter.inspect_tree() end, "Syntax tree")

-- Space u: toggles (GaussianVim extras)
map("n", "<leader>uw", function() vim.wo.wrap = not vim.wo.wrap end, "Wrap long lines")
map("n", "<leader>ur", function() vim.wo.relativenumber = not vim.wo.relativenumber end, "Relative line numbers")
map("n", "<leader>ud", function() vim.diagnostic.enable(not vim.diagnostic.is_enabled()) end, "Error messages on/off")
map("n", "<leader>us", function() vim.wo.spell = not vim.wo.spell end, "Spell check")
map("n", "<leader>ug", function() require("gv.tex").toggle_grammar() end, "Grammar check (LanguageTool)")
map("n", "<leader>ua", function() require("gv.tex").toggle_auto() end, "Instant maths aliases (LaTeX)")
map("n", "<leader>ui", function()
  if Snacks.indent.enabled then Snacks.indent.disable() else Snacks.indent.enable() end
end, "Indent guides")
map("n", "<leader>ut", function() require("gv.transparent").toggle() end, "Transparent background")
map("n", "<leader>uc", function() vim.wo.cursorline = not vim.wo.cursorline end, "Cursor line")

-- Space S: sessions (your dashboard's "Restore")
map("n", "<leader>Ss", function() require("persistence").load() end, "Restore session (this folder)")
map("n", "<leader>Sl", function() require("persistence").load({ last = true }) end, "Restore last session")
map("n", "<leader>SS", function() require("persistence").select() end, "Pick a session")

-- your LunarVim keys
map("n", "|", "<cmd>vsplit<cr>", "Split side by side")
map("n", "-", "<cmd>split<cr>", "Split top / bottom")

-- windows: Ctrl + h/j/k/l moves between splits, Ctrl + arrows resizes
map("n", "<C-h>", "<C-w>h", "Window left")
map("n", "<C-j>", "<C-w>j", "Window below")
map("n", "<C-k>", "<C-w>k", "Window above")
map("n", "<C-l>", "<C-w>l", "Window right")
map("n", "<C-Up>", "<cmd>resize -2<cr>", "Resize")
map("n", "<C-Down>", "<cmd>resize +2<cr>", "Resize")
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", "Resize")
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", "Resize")

-- quickfix list
map("n", "]q", "<cmd>cnext<cr>", "Next quickfix item")
map("n", "[q", "<cmd>cprev<cr>", "Previous quickfix item")
map("n", "<C-q>", function()
  local open = vim.iter(vim.fn.getwininfo()):any(function(w) return w.quickfix == 1 end)
  vim.cmd(open and "cclose" or "copen")
end, "Toggle quickfix list")

-- terminal (LunarVim's toggleterm): Ctrl+\ floating, Alt+1 below, Alt+2 right, Alt+3 floating
local function term(position)
  return function() Snacks.terminal.toggle(nil, { win = { position = position }, count = position == "float" and 1 or position == "bottom" and 2 or 3 }) end
end
for _, mode in ipairs({ "n", "t" }) do
  map(mode, [[<C-\>]], term("float"), "Terminal (floating)")
  map(mode, "<A-1>", term("bottom"), "Terminal (below)")
  map(mode, "<A-2>", term("right"), "Terminal (right)")
  map(mode, "<A-3>", term("float"), "Terminal (floating)")
end
map("t", "<C-h>", [[<C-\><C-n><C-w>h]], "Window left")
map("t", "<C-j>", [[<C-\><C-n><C-w>j]], "Window below")
map("t", "<C-k>", [[<C-\><C-n><C-w>k]], "Window above")
map("t", "<C-l>", [[<C-\><C-n><C-w>l]], "Window right")

-- editing (LunarVim): keep selection when indenting, Alt+j/k moves lines
map("v", "<", "<gv", "Indent left")
map("v", ">", ">gv", "Indent right")
map("n", "<A-j>", "<cmd>m .+1<cr>==", "Move line down")
map("n", "<A-k>", "<cmd>m .-2<cr>==", "Move line up")
map("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi", "Move line down")
map("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi", "Move line up")
map("x", "<A-j>", ":m '>+1<cr>gv=gv", "Move selection down")
map("x", "<A-k>", ":m '<-2<cr>gv=gv", "Move selection up")
map("i", "jk", "<esc>", "Leave insert mode")
map("i", "kj", "<esc>", "Leave insert mode")
map("n", "<C-s>", "<cmd>w<cr>", "Save")
map("i", "<C-s>", "<esc><cmd>w<cr>", "Save")

-- like project.nvim in LunarVim: the working folder follows the project of the file you open
vim.api.nvim_create_autocmd("BufEnter", {
  callback = function(ev)
    if vim.bo[ev.buf].buftype ~= "" or vim.api.nvim_buf_get_name(ev.buf) == "" then return end
    local r = vim.fs.root(ev.buf, { ".git", "pyproject.toml", "setup.py", "Makefile", "latexmkrc", ".latexmkrc" })
    if r and r ~= vim.uv.cwd() then vim.fn.chdir(r) end
  end,
})

-- run card (lua/gv/run.lua): F5 runs the file, Shift+F5 stops
local run = function(fn) return function(...) require("gv.run")[fn](...) end end
for _, mode in ipairs({ "n", "i" }) do
  map(mode, "<F5>", function() vim.cmd.stopinsert(); require("gv.run").run() end, "Run file")
  map(mode, "<S-F5>", run("stop"), "Stop running")
end
map("n", "<leader>rr", function() require("gv.run").run() end, "Run file (F5)")
map("n", "<leader>ra", run("run_with_args"), "Run with arguments…")
map("n", "<leader>rs", run("stop"), "Stop (Shift+F5)")
map("n", "<leader>rp", run("toggle"), "Show / hide the run card")
map("n", "<leader>rq", run("close"), "Close the run card")
map("n", "<leader>ro", run("focus_output"), "Type into the running program")
map("n", "<leader>rz", run("zoom"), "Zoom the plot (in the card)")
map("n", "<leader>rw", run("window"), "Plot in a real window (matplotlib toolbar)")
map("n", "<leader>r]", function() require("gv.run").next_item(1) end, "Next plot / file")
map("n", "<leader>r[", function() require("gv.run").next_item(-1) end, "Previous plot / file")
map("n", "<leader>rc", run("close_plots"), "Clear the plots")
map("n", "<leader>rf", run("focus_plot"), "Go to the viewer (plot / file)")
map("n", "<leader>ri", run("console"), "Python console with this file loaded")

-- one-key git: Alt+G = git menu, Alt+Shift+G = Source Control card
-- (Space g m / Space G do the same)
for _, mode in ipairs({ "n", "i", "v", "t" }) do
  map(mode, "<A-g>", function() vim.cmd.stopinsert(); require("gv.gitmenu").open() end, "Git menu")
  map(mode, "<A-G>", function() vim.cmd.stopinsert(); require("gv.scm").toggle() end, "Source control")
end
