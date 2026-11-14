-- Claude inside gv and GaussianTeX: Claude Code runs in a floating panel on the
-- right (in your project folder), and these keys hand it the right context:
--
--   Space a a   show / hide the Claude panel (Ctrl+q inside it also hides it;
--               while hidden it waits as "Claude" in the bar at the bottom right:
--               click it, or Ctrl+q in the editor, to bring it back)
--   drag its top edge to move it, its bottom / right edge to resize it
--   (Alt+arrows / Alt+Shift+arrows too); select text with the mouse to copy it
--   Space a e   explain and fix the error on this line
--   Space a s   (visual) send the selection; you type your question after it
--   Space a f   review this file: bugs, logic, physics / maths mistakes
--   Space a r   the last run failed (F5): find the cause
--   Space a l   (.tex) fix the LaTeX compile errors
--   Space a w   (.tex) check this paragraph: wording, grammar, physics logic
--   a           (in the run card) ask Claude about the failed run
--
-- Claude edits files itself when you allow it; gv reloads them when it does.
-- Needs the `claude` command (Claude Code): https://claude.ai/install.sh
local M = {}

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Claude" }) end

local function claude_bin()
  for _, p in ipairs({ "claude", vim.fn.expand("~/.local/bin/claude"), vim.fn.expand("~/.claude/local/claude") }) do
    if vim.fn.executable(p) == 1 then return p end
  end
end

local function root()
  local ok, r = pcall(vim.fn.eval, "b:vimtex.root")
  if ok and type(r) == "string" and r ~= "" then return r end
  return vim.fs.root(0, { ".git", "pyproject.toml", "main.tex", "Makefile" }) or vim.fn.getcwd()
end

local term
local function opts(cwd)
  return {
    cwd = cwd,
    win = {
      position = "float", border = "rounded", title = " \u{f0335} Claude ", title_pos = "left",
      width = 0.44, height = 0.9, row = 1, col = math.floor(vim.o.columns * 0.55),
      footer = " Ctrl+q hide (back: bottom bar) · drag edges · select copies ",
      footer_pos = "right",
      keys = { hide = { "<C-q>", "hide", mode = { "t", "n" } } },
    },
  }
end

function M.toggle()
  local bin = claude_bin()
  if not bin then
    return notify("Claude Code isn't installed. In a terminal:  curl -fsSL https://claude.ai/install.sh | bash   then run  claude  once to log in", vim.log.levels.WARN)
  end
  if term and term:valid() then return term:toggle() end
  term = Snacks.terminal.open({ bin }, opts(root()))
  return term
end

-- open the panel (if needed) and paste text into Claude's prompt; submit = press Enter too
function M.send(text, submit)
  if not (term and term:valid()) then
    if not M.toggle() then return end
    -- Claude needs a moment to start before it reads the prompt
    return vim.defer_fn(function() M.send(text, submit) end, 2500)
  end
  if not term:win_valid() then term:show() end
  local chan = vim.bo[term.buf].channel
  vim.fn.chansend(chan, "\27[200~" .. text .. "\27[201~")       -- as a paste: newlines stay newlines
  if submit then vim.defer_fn(function() vim.fn.chansend(chan, "\r") end, 150) end
  vim.api.nvim_set_current_win(term.win)
  vim.cmd.startinsert()
end

local function rel(file) return vim.fn.fnamemodify(file, ":.") end
local function is_tex() return vim.bo.filetype == "tex" or vim.bo.filetype == "plaintex" end

function M.error_here()
  local file, line = vim.api.nvim_buf_get_name(0), vim.api.nvim_win_get_cursor(0)[1]
  local ds = vim.diagnostic.get(0, { lnum = line - 1 })
  local msgs = {}
  for _, d in ipairs(ds) do msgs[#msgs + 1] = ("- %s: %s"):format(d.source or "error", d.message) end
  local what = #msgs > 0 and ("It reports:\n" .. table.concat(msgs, "\n")) or "Something on this line is wrong or unclear to me."
  M.send(("In @%s line %d:\n%s\n\nExplain the cause in simple words and fix it."):format(rel(file), line, what), true)
end

function M.selection()
  local s, e = vim.fn.getpos("'<"), vim.fn.getpos("'>")
  local lines = vim.api.nvim_buf_get_lines(0, s[2] - 1, e[2], false)
  M.send(("From @%s lines %d-%d:\n```%s\n%s\n```\n"):format(rel(vim.api.nvim_buf_get_name(0)), s[2], e[2],
    vim.bo.filetype, table.concat(lines, "\n")), false)
end

function M.review_file()
  local f = rel(vim.api.nvim_buf_get_name(0))
  if is_tex() then
    M.send(("Read @%s. Check the physics and maths for mistakes (signs, factors, definitions, inconsistent notation), the logic of the argument, and the LaTeX. List problems with line numbers, most important first. Don't edit yet."):format(f), true)
  else
    M.send(("Review @%s: bugs, logic errors, numerical problems (precision, stability, units), and simpler ways to write it. List them with line numbers, most important first. Don't edit yet."):format(f), true)
  end
end

function M.run_failed()
  local ok, out = pcall(function() return require("gv.run").last_output() end)
  if not ok or not out then return notify("Run something with F5 first") end
  M.send(("Running @%s failed. The end of the output:\n```\n%s\n```\nFind the cause and fix it."):format(rel(out.file), out.text), true)
end

function M.latex_errors()
  local qf = vim.fn.getqflist()
  if #qf == 0 then return notify("No LaTeX errors: compile with F5 first") end
  local lines = {}
  for i = 1, math.min(#qf, 30) do
    local e = qf[i]
    lines[#lines + 1] = ("%s:%d: %s"):format(e.bufnr > 0 and rel(vim.api.nvim_buf_get_name(e.bufnr)) or "?", e.lnum, e.text)
  end
  M.send("My LaTeX project doesn't compile cleanly. latexmk reports:\n```\n" .. table.concat(lines, "\n") .. "\n```\nFix the causes in the .tex / .bib files.", true)
end

function M.paragraph()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local all = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local s, e = row, row
  while s > 1 and all[s - 1]:match("%S") do s = s - 1 end
  while e < #all and all[e + 1]:match("%S") do e = e + 1 end
  M.send(("Check this paragraph of @%s (lines %d-%d) for wording, grammar and the physics logic. Suggest a corrected version, keeping the LaTeX as is:\n```latex\n%s\n```"):format(
    rel(vim.api.nvim_buf_get_name(0)), s, e, table.concat(vim.list_slice(all, s, e), "\n")), true)
end

-- while hidden, Claude waits in the dock (the bar at the bottom right)
local function show()
  if not (term and term:valid()) then return M.toggle() end
  term:show()
  if term:win_valid() then vim.api.nvim_set_current_win(term.win); vim.cmd.startinsert() end
end
require("gv.dock").provide(function()
  if term and term:valid() and not term:win_valid() then
    return { key = "claude", name = "Claude", icon = "\u{f0335}", restore = show }
  end
end)
vim.api.nvim_create_autocmd({ "WinClosed", "WinNew", "BufWinEnter" }, {
  group = vim.api.nvim_create_augroup("gv_claude_dock", { clear = true }),
  callback = function() vim.schedule(require("gv.dock").refresh) end,
})

-- files Claude changed: reload them (unless you changed them too)
vim.o.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  callback = function() if vim.fn.mode() == "n" and vim.fn.getcmdwintype() == "" then pcall(vim.cmd.checktime) end end,
})

return M
