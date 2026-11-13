-- GaussianTeX writing aids for .tex files (the server settings are in lua/gv/lsp.lua):
--
--   spelling   Neovim's own spell check, as you type: wrong words get a red
--              wavy underline. vimtex keeps \commands, labels and maths out
--              of it. z= suggestions (a menu at the cursor), zg adds the word
--              to your dictionary, ]s / [s next / previous wrong word.
--   grammar    LanguageTool (ltex-ls-plus): "This are", "a apple", "the the"
--              get underlined a few seconds after you stop typing. gl says
--              what's wrong; the correction shows under the mark, z= picks
--              it (Space l a too). Space u g on / off
--              (it is Java and takes a few hundred MB while on).
--   compile    F5 or the ▶ Compile button at the top right; PDF button = zathura
--   rephrase   Space l p: the paragraph (or selection) rewritten by the local Qwen
--   files      Space e or the Files button: the project as a tree, U uploads
--   figures    cursor on \includegraphics{...}: the figure pops up under it
--   aliases    snippets/tex.json: figure, table, matrix, frac, intgrl, pdv, dv, ...
--              (type the word, Tab/Enter); picking an environment after \begin{
--              gives the same whole block, \frac / \section / ... get their braces.
--              All plain LaTeX, so the file compiles anywhere.
--   export     Space l z: the project as a .zip in Downloads, no build files
--   commands   texlab: typing \sec, \begin{, \ref{, \cite{ opens the menu of
--              commands, environments, your labels and your bibliography keys,
--              with the snippets (sec, begin, equation, figure, table, ...).
--              Picking an environment after \begin{ adds its \end{...} too.
local M = {}

local function notify(msg) vim.notify(msg, vim.log.levels.INFO, { title = "GaussianTeX" }) end

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "tex", "plaintex" },
  group = vim.api.nvim_create_augroup("gv_tex", { clear = true }),
  callback = function(ev)
    vim.opt_local.spell = true
    vim.opt_local.spelllang = "en_us"
    vim.b[ev.buf].snacks_image_attached = true    -- Snacks: don't draw over the LaTeX you are writing
    -- spelling suggestions in a small searchable list instead of a full screen
    -- suggestions for what's under the cursor: the grammar fix, or the spelling
    vim.keymap.set("n", "z=", function() M.suggest() end, { buffer = ev.buf, desc = "Suggestions (grammar / spelling)" })
  end,
})

-- Overleaf-style: picking an environment from the menu after \begin{ also
-- writes its \end{...} and puts the cursor on the line in between (not when
-- that environment is already closed further down)
-- the whole block for an environment, from snippets/tex.json (the figure,
-- table, equation, ... snippets), so \begin{figure} gives what "figure" does
local templates
local function env_template(name)
  if not templates then
    templates = {}
    local fd = io.open(vim.fn.stdpath("config") .. "/snippets/tex.json", "r")
    if fd then
      local ok, data = pcall(vim.json.decode, fd:read("*a"))
      fd:close()
      for _, sn in pairs(ok and data or {}) do
        local body = table.concat(type(sn.body) == "table" and sn.body or { sn.body }, "\n")
        local env = body:match("^\\\\begin{([%w%*]+)}")
        if env and not templates[env] then templates[env] = body end
      end
    end
  end
  return templates[name]
end

-- Overleaf-style: picking \frac, \sqrt, \section, ... from the menu also
-- writes their braces, and Tab jumps from one to the next
local ARGS = {
  frac = "{$1}{$2}", dfrac = "{$1}{$2}", tfrac = "{$1}{$2}", binom = "{$1}{$2}", sqrt = "{$1}",
  textbf = "{$1}", textit = "{$1}", emph = "{$1}", texttt = "{$1}", text = "{$1}", underline = "{$1}",
  mathrm = "{$1}", mathbf = "{$1}", mathcal = "{$1}", mathbb = "{$1}", boldsymbol = "{$1}",
  hat = "{$1}", bar = "{$1}", tilde = "{$1}", vec = "{$1}", dot = "{$1}", ddot = "{$1}", overline = "{$1}",
  chapter = "{$1}", section = "{$1}", subsection = "{$1}", subsubsection = "{$1}", paragraph = "{$1}",
  ["section*"] = "{$1}", ["subsection*"] = "{$1}", ["chapter*"] = "{$1}",
  caption = "{$1}", label = "{$1}", ref = "{$1}", eqref = "{$1}", cite = "{$1}", footnote = "{$1}",
  url = "{$1}", href = "{$1}{$2}", input = "{$1}", include = "{$1}", usepackage = "{$1}",
  includegraphics = "[width=${1:0.8}\\\\linewidth]{$2}",
}

function M.after_accept()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local before, after = line:sub(1, col), line:sub(col + 1)
  local cmd = before:match("\\([%a]+%*?)$")
  if cmd and ARGS[cmd] and not after:match("^[%[{]") then
    vim.snippet.expand(ARGS[cmd] .. "$0")
    return
  end
  M.close_env()
end

function M.close_env()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local before, after = line:sub(1, col), line:sub(col + 1)
  local name = before:match("\\begin{([%w%*]+)}?$")
  if not name or not (after == "" or after:match("^}%s*$")) then return end
  local depth = 0
  local esc = vim.pesc(name)
  for _, l in ipairs(vim.api.nvim_buf_get_lines(0, row, row + 300, false)) do
    for kind in l:gmatch("\\(%a+){" .. esc .. "}") do
      if kind == "begin" then depth = depth + 1
      elseif kind == "end" then
        if depth == 0 then return end                 -- already closed
        depth = depth - 1
      end
    end
  end
  -- a known environment: the whole block (figure: \centering, \includegraphics,
  -- \caption, \label; Tab jumps through them)
  local body = env_template(name)
  if body then
    local s = before:find("\\begin{[%w%*]+}?$")
    vim.api.nvim_set_current_line(line:sub(1, s - 1) .. after:gsub("^}", "", 1))
    vim.api.nvim_win_set_cursor(0, { row, s - 1 })
    vim.snippet.expand(body)
    return
  end
  local indent = line:match("^%s*")
  local step = vim.bo.expandtab and string.rep(" ", vim.fn.shiftwidth()) or "\t"
  vim.api.nvim_buf_set_lines(0, row - 1, row, false,
    { before:gsub("}$", "") .. "}", indent .. step, indent .. "\\end{" .. name .. "}" })
  vim.api.nvim_win_set_cursor(0, { row + 1, #indent + #step })
end

vim.api.nvim_create_autocmd("User", {
  pattern = "BlinkCmpAccept",
  group = vim.api.nvim_create_augroup("gv_tex_env", { clear = true }),
  callback = function()
    local ft = vim.bo.filetype
    if ft == "tex" or ft == "plaintex" then vim.schedule(M.after_accept) end
  end,
})

-- Grammar: LanguageTool (ltex-ls-plus, Java). Only for .tex files, at most
-- 512 MB. Spelling is left to Neovim's own spell check (instant; z=, zg), so
-- LanguageTool's spelling rule is off and no word is underlined twice.
-- NUMBERS_IN_WORDS misfires after equations and on "2D", "SU2", "H2O".
-- "Disable rule" / "Hide false positive" (Space l a) are remembered in
-- ~/.local/share/gaussianvim/ltex.json.
local STORE = vim.fn.stdpath("data") .. "/ltex.json"
local KEYS = { dictionary = "words", disabledRules = "ruleIds", hiddenFalsePositives = "falsePositives" }
local store = { dictionary = {}, disabledRules = {}, hiddenFalsePositives = {} }
do
  local f = io.open(STORE, "r")
  if f then
    local ok, data = pcall(vim.json.decode, f:read("*a"))
    f:close()
    if ok and type(data) == "table" then
      for key in pairs(KEYS) do store[key] = type(data[key]) == "table" and data[key] or {} end
    end
  end
end

local settings = {
  ltex = {
    enabled = { "latex", "tex" },
    language = "en-US",
    completionEnabled = false,
    disabledRules = { ["en-US"] = { "MORFOLOGIK_RULE_EN_US", "NUMBERS_IN_WORDS" } },
    dictionary = {},
    hiddenFalsePositives = {},
  },
}

-- add what you chose (store) to the settings the server reads
local function merge_store()
  for key in pairs(KEYS) do
    for lang, list in pairs(store[key]) do
      local t = settings.ltex[key][lang] or {}
      for _, v in ipairs(list) do
        if not vim.tbl_contains(t, v) then t[#t + 1] = v end
      end
      settings.ltex[key][lang] = t
    end
  end
end
merge_store()

vim.lsp.config("ltex_plus", {
  filetypes = { "tex", "plaintex" },
  -- LanguageTool needs its 512 MB heap (with less it hangs instead of
  -- checking; -XX:TieredStopAtLevel=1 hangs it too): about 700 MB while on
  cmd_env = { JAVA_OPTS = "-Xms64m -Xmx512m -XX:+UseSerialGC" },
  settings = settings,
})

-- LanguageTool leaves these code actions to the editor: remember the choice,
-- tell the server (it checks the file again)
for cmd, key in pairs({ ["_ltex.addToDictionary"] = "dictionary", ["_ltex.disableRules"] = "disabledRules",
  ["_ltex.hideFalsePositives"] = "hiddenFalsePositives" }) do
  vim.lsp.commands[cmd] = function(command, ctx)
    local arg = command.arguments and command.arguments[1] or {}
    for lang, list in pairs(arg[KEYS[key]] or {}) do
      store[key][lang] = store[key][lang] or {}
      for _, v in ipairs(list) do
        if not vim.tbl_contains(store[key][lang], v) then table.insert(store[key][lang], v) end
      end
    end
    local f = io.open(STORE, "w")
    if f then f:write(vim.json.encode(store)); f:close() end
    merge_store()
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    if client then
      client.settings = vim.tbl_deep_extend("force", client.settings or {}, settings)
      client:notify("workspace/didChangeConfiguration", { settings = client.settings })
    end
    notify(key == "disabledRules" and "Grammar rule switched off" or key == "dictionary" and "Added to the dictionary"
      or "Won't flag that again")
  end
end

-- grammar: on unless switched off in this session
M.grammar = true
vim.lsp.enable("ltex_plus")

-- Compile and PDF (Overleaf's Recompile button and PDF pane) -----------------
-- F5, or the ▶ Compile button at the top right of a .tex window: latexmk
-- (through vimtex) compiles, and from then on compiles again every time you
-- save. The PDF opens in zathura beside gv and refreshes itself; the PDF
-- button (Space l v) shows the spot under the cursor, Ctrl+click in the PDF
-- jumps back to that line here. Errors get marks on their lines and the button
-- says how many: click it (or Space l e) for the list. Shift+F5 stops.
local ns_err = vim.api.nvim_create_namespace("gv_latex_errors")
local C = { state = "idle", errors = 0, warnings = 0 }
M.compile_state = C

local function refresh_bar()
  pcall(function() require("lualine").refresh({ place = { "winbar" } }) end)
end

local function is_running()
  return vim.b.vimtex ~= nil and vim.fn.eval("b:vimtex.compiler.is_running()") == 1
end

function M.compile()
  if vim.b.vimtex == nil then return notify("Open the .tex file first (vimtex isn't active here)") end
  local modified = vim.bo.modified
  if modified then vim.cmd("silent write") end
  if not is_running() then
    vim.cmd("VimtexCompile")
    notify("Compiling. From now on it compiles again every time you save (Space w); the PDF opens beside gv")
  elseif not modified then
    notify("Up to date. It compiles again every time you save")
  end
end

function M.stop()
  if is_running() then vim.cmd("VimtexStop"); notify("Compiling stopped") else notify("Not compiling") end
end

-- the compiled PDF's path ("" before the first compile)
local function pdf_path()
  local ok, p = pcall(vim.fn.eval, "b:vimtex.compiler.get_file('pdf')")
  return ok and type(p) == "string" and p or ""
end

function M.view()
  if vim.b.vimtex == nil then return notify("Open the .tex file first") end
  if vim.fn.executable("zathura") == 0 then
    return notify("The PDF viewer isn't installed yet. In a terminal:  sudo dnf install zathura zathura-pdf-mupdf")
  end
  if pdf_path() == "" or vim.fn.filereadable(pdf_path()) == 0 then
    notify("No PDF yet: compiling first (it opens when done)")
    return M.compile()
  end
  vim.cmd("VimtexView")
end

function M.errors()
  if #vim.fn.getqflist() == 0 then return notify("No errors or warnings") end
  Snacks.picker.qflist({ title = "LaTeX errors and warnings" })
end

-- what the button at the top right says and does
function M.button()
  if C.state == "compiling" then return " \u{f110} Compiling… ", "GvRunBusy" end
  if C.state == "failed" then
    return (" \u{f00d} %d error%s "):format(C.errors, C.errors == 1 and "" or "s"), "GvRunFail"
  end
  if C.state == "ok" then
    return " \u{f00c} Compiled" .. (C.secs and ("  " .. C.secs) or "")
      .. (C.warnings > 0 and ("  \u{f071} " .. C.warnings) or "") .. " ", "GvRunOk"
  end
  return " \u{f04b} Compile ", "GvRunBusy"
end

function M.button_click()
  if C.state == "failed" or (C.state == "ok" and C.warnings > 0) then return M.errors() end
  if C.state ~= "compiling" then M.compile() end
end

-- compile errors as marks on their lines, like Overleaf
local diag_bufs = {}
local function collect()
  for b in pairs(diag_bufs) do
    if vim.api.nvim_buf_is_valid(b) then vim.diagnostic.reset(ns_err, b) end
  end
  diag_bufs = {}
  local errors, warnings = 0, 0
  for _, e in ipairs(vim.fn.getqflist()) do
    local err = e.type == "E" or e.type == "e"
    if err then errors = errors + 1 else warnings = warnings + 1 end
    if e.valid == 1 and e.bufnr > 0 then
      diag_bufs[e.bufnr] = diag_bufs[e.bufnr] or {}
      table.insert(diag_bufs[e.bufnr], {
        lnum = math.max(0, e.lnum - 1), col = 0, source = "LaTeX", message = e.text,
        severity = err and vim.diagnostic.severity.ERROR or vim.diagnostic.severity.WARN,
      })
    end
  end
  for b, list in pairs(diag_bufs) do vim.diagnostic.set(ns_err, b, list) end
  C.errors, C.warnings = errors, warnings
end

-- after the PDF opens (or a Ctrl+click in it), the keyboard goes back to gv,
-- as in Overleaf; only taken from zathura, never from another app
local function focus_gv(delays)
  local wid = vim.env.WINDOWID
  if not wid or vim.fn.executable("xdotool") == 0 then return end
  for _, ms in ipairs(delays) do
    vim.defer_fn(function()
      vim.system({ "xdotool", "getactivewindow", "getwindowclassname" }, { text = true }, function(r)
        if (r.stdout or ""):lower():match("zathura") then
          if vim.fn.executable("i3-msg") == 1 then vim.system({ "i3-msg", "-q", "[id=" .. wid .. "] focus" })
          else vim.system({ "xdotool", "windowactivate", wid }) end
        end
      end)
    end, ms)
  end
end

local grp = vim.api.nvim_create_augroup("gv_tex_compile", { clear = true })
local function on(event, fn) vim.api.nvim_create_autocmd("User", { pattern = event, group = grp, callback = fn }) end
on("VimtexEventCompiling", function() C.state, C.t0 = "compiling", vim.uv.hrtime(); refresh_bar() end)
on("VimtexEventCompileStarted", function() C.state, C.t0 = "compiling", vim.uv.hrtime(); refresh_bar() end)
on("VimtexEventCompileSuccess", function()
  C.state = "ok"
  local secs = C.t0 and (vim.uv.hrtime() - C.t0) / 1e9
  C.secs = secs and secs >= 0.1 and ("%.1f s"):format(secs) or nil   -- nothing to redo: no time
  collect(); refresh_bar()
end)
on("VimtexEventCompileFailed", function()
  C.state = "failed"
  collect(); refresh_bar()
  notify(("Compile failed: %d error%s. Click the red button (or Space l e) for the list"):format(C.errors, C.errors == 1 and "" or "s"))
end)
on("VimtexEventCompileStopped", function()
  if C.state == "compiling" then C.state = "idle" end
  refresh_bar()
end)
on("VimtexEventView", function() focus_gv({ 400, 1200 }) end)
on("VimtexEventViewReverse", function() focus_gv({ 0 }) end)

-- keys in .tex files (F5 / Shift+F5 go through the run card's keys: lua/gv/run.lua)
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "tex", "plaintex" },
  group = grp,
  callback = function(ev)
    vim.keymap.set("n", "<leader>lv", M.view, { buffer = ev.buf, desc = "PDF: show this spot (zathura)" })
    vim.keymap.set("n", "<leader>lc", M.compile, { buffer = ev.buf, desc = "Compile (then on every save)" })
    vim.keymap.set("n", "<leader>e", M.files, { buffer = ev.buf, desc = "Project files (U uploads)" })
    vim.keymap.set("n", "<leader>lz", function() M.export_zip() end, { buffer = ev.buf, desc = "Export the project as .zip (Downloads)" })
    vim.keymap.set("n", "<leader>lp", function() require("gv.rephrase").start(false) end, { buffer = ev.buf, desc = "Rephrase this paragraph (local Qwen)" })
    vim.keymap.set("x", "<leader>lp", function()
      vim.cmd("normal! \27")                       -- leave visual mode so '< '> are set
      require("gv.rephrase").start(true)
    end, { buffer = ev.buf, desc = "Rephrase the selection (local Qwen)" })
  end,
})

-- Grammar suggestions -------------------------------------------------------------
-- Resting the cursor on a grammar mark shows LanguageTool's correction in a
-- small card under it ("could of → could have"); z= opens the choices at the
-- cursor (Enter or the number takes one), as it does for a misspelled word.

local function grammar_at_cursor()
  local client = vim.lsp.get_clients({ bufnr = 0, name = "ltex_plus" })[1]
  if not client then return end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  for _, d in ipairs(vim.diagnostic.get(0, { namespace = vim.lsp.diagnostic.get_namespace(client.id), lnum = row - 1 })) do
    local last = d.end_lnum == d.lnum and d.end_col or math.huge
    if col >= d.col and col <= last then return d, client end
  end
end

-- LanguageTool's fixes for one mark: replacements (with the new text) and the rest
local function grammar_actions(d, client, cb)
  local lsp_d = d.user_data and d.user_data.lsp
  if not lsp_d then return cb({}, {}) end
  local params = { textDocument = vim.lsp.util.make_text_document_params(0), range = lsp_d.range, context = { diagnostics = { lsp_d } } }
  local buf = vim.api.nvim_get_current_buf()
  client:request("textDocument/codeAction", params, function(_, result)
    local fixes, other = {}, {}
    for _, a in ipairs(result or {}) do
      local text
      local edit = a.edit
      if edit then
        for _, edits in pairs(edit.changes or {}) do text = text or (edits[1] and edits[1].newText) end
        for _, dc in ipairs(edit.documentChanges or {}) do text = text or (dc.edits and dc.edits[1] and dc.edits[1].newText) end
      end
      if text then fixes[#fixes + 1] = { action = a, text = text } else other[#other + 1] = { action = a } end
    end
    vim.schedule(function() cb(fixes, other) end)
  end, buf)
end

local hint = {}
local function close_hint()
  if hint.win and vim.api.nvim_win_is_valid(hint.win) then vim.api.nvim_win_close(hint.win, true) end
  hint = {}
end

local function show_hint()
  local d, client = grammar_at_cursor()
  if not d then return close_hint() end
  local key = ("%d:%d:%d:%s"):format(vim.api.nvim_get_current_buf(), d.lnum, d.col, d.message)
  if hint.key == key then return end
  close_hint()
  hint.key = key
  grammar_actions(d, client, function(fixes)
    if hint.key ~= key or #fixes == 0 or vim.fn.mode() ~= "n" then return end
    local ok, flagged = pcall(vim.api.nvim_buf_get_text, 0, d.lnum, d.col, d.end_lnum, d.end_col, {})
    flagged = ok and table.concat(flagged, " ") or ""
    local picks = {}
    for i = 1, math.min(3, #fixes) do picks[i] = fixes[i].text == "" and "(delete)" or fixes[i].text end
    local arrow = "  \u{2192}  "
    local text = " " .. flagged .. arrow .. table.concat(picks, "  ·  ") .. "   z= fix "
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
    local hns = vim.api.nvim_create_namespace("gv_grammar_hint")
    local a = 1 + #flagged
    vim.api.nvim_buf_set_extmark(buf, hns, 0, 1, { end_col = a, hl_group = "GvDeleted" })
    vim.api.nvim_buf_set_extmark(buf, hns, 0, a + #arrow, { end_col = #text - #"   z= fix ", hl_group = "DiagnosticOk" })
    vim.api.nvim_buf_set_extmark(buf, hns, 0, #text - #"   z= fix ", { end_col = #text, hl_group = "GvMenuDim" })
    hint.win = vim.api.nvim_open_win(buf, false, {
      relative = "cursor", row = 1, col = 0, width = math.min(vim.fn.strdisplaywidth(text), vim.o.columns - 4), height = 1,
      style = "minimal", border = "rounded", focusable = false, zindex = 45,
    })
    vim.bo[buf].bufhidden = "wipe"
    vim.wo[hint.win].winhighlight = "Normal:GvMenu,FloatBorder:GvMenuBorder"
  end)
end

-- z=: the grammar choices at a grammar mark, else spelling suggestions
function M.suggest()
  close_hint()
  local d, client = grammar_at_cursor()
  if d then
    return grammar_actions(d, client, function(fixes, other)
      local items = {}
      for i, f in ipairs(fixes) do
        items[#items + 1] = { icon = "\u{f00c}", label = f.text == "" and "(delete it)" or f.text, key = i <= 9 and tostring(i) or nil,
          run = function() vim.lsp.util.apply_workspace_edit(f.action.edit, client.offset_encoding) end }
      end
      if #items > 0 and #other > 0 then items[#items + 1] = "-" end
      for _, o in ipairs(other) do
        items[#items + 1] = { icon = "\u{f0ad}", label = o.action.title,
          run = function() if o.action.command then client:exec_cmd(o.action.command, { bufnr = 0 }) end end }
      end
      if #items == 0 then return notify(d.message) end
      require("gv.menu").open({ title = "Grammar", anchor = "cursor", items = items })
    end)
  end
  local word = vim.fn.expand("<cword>")
  local bad = vim.fn.spellbadword(word)[1]
  if bad == "" then return notify("Nothing to fix under the cursor") end
  local items = {}
  for i, sug in ipairs(vim.fn.spellsuggest(bad, 9)) do
    items[#items + 1] = { icon = "\u{f00c}", label = sug, key = tostring(i), run = function() vim.cmd("normal! " .. i .. "z=") end }
  end
  items[#items + 1] = "-"
  items[#items + 1] = { icon = "\u{f0415}", label = ("Add \"%s\" to your dictionary"):format(bad), key = "a", run = function() vim.cmd("normal! zg") end }
  require("gv.menu").open({ title = "Spelling", anchor = "cursor", items = items })
end

vim.api.nvim_create_autocmd("CursorHold", {
  group = grp,
  callback = function()
    local ft = vim.bo.filetype
    if ft == "tex" or ft == "plaintex" then show_hint() end
  end,
})
vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "BufLeave", "WinLeave" }, {
  group = grp,
  callback = function()
    if not hint.key then return end
    local d = grammar_at_cursor()
    local key = d and ("%d:%d:%d:%s"):format(vim.api.nvim_get_current_buf(), d.lnum, d.col, d.message)
    if key ~= hint.key or vim.fn.mode() ~= "n" then close_hint() end
  end,
})

-- Project files (Overleaf's file panel) --------------------------------------------
-- Space e (or the Files button) in a .tex file: the folder of the main .tex as
-- a tree on the left. Enter opens a file, P previews it (figures too), a adds
-- a file or folder, r renames, d deletes, o opens with its app, and
-- U uploads: a "choose files" window (Downloads first) copies them into the
-- folder under the cursor.

local function project_root()
  local ok, root = pcall(vim.fn.eval, "b:vimtex.root")
  if ok and type(root) == "string" and root ~= "" then return root end
  return vim.fs.dirname(vim.api.nvim_buf_get_name(0))
end

local function upload(picker)
  local dir = picker:dir()
  if vim.fn.executable("zenity") == 0 then return notify("Can't open a file chooser (zenity isn't installed)") end
  local start = vim.fn.isdirectory(vim.fn.expand("~/Downloads")) == 1 and vim.fn.expand("~/Downloads/") or vim.fn.expand("~/")
  vim.system({ "zenity", "--file-selection", "--multiple", "--separator=\n", "--filename=" .. start,
    "--title=Upload into " .. vim.fn.fnamemodify(dir, ":~") }, { text = true }, function(r)
    vim.schedule(function()
      if r.code == 1 then return end                      -- closed without choosing
      if r.code ~= 0 then return notify("The file chooser didn't open (zenity exited with " .. r.code .. ")") end
      local files = vim.split(vim.trim(r.stdout or ""), "\n", { trimempty = true })
      local fresh, existing = {}, {}
      for _, src in ipairs(files) do
        local dst = dir .. "/" .. vim.fs.basename(src)
        if vim.uv.fs_stat(dst) then existing[#existing + 1] = { src, dst } else fresh[#fresh + 1] = { src, dst } end
      end
      local function copy(list)
        local last
        for _, f in ipairs(list) do
          if vim.uv.fs_copyfile(f[1], f[2]) then last = f[2] else notify("Couldn't copy " .. f[1]) end
        end
        if last then
          local Tree = require("snacks.explorer.tree")
          Tree:open(dir)
          Tree:refresh(dir)
          require("snacks.explorer.actions").update(picker, { target = last })
        end
        return last
      end
      if #fresh > 0 and copy(fresh) then
        notify(("Uploaded %d file%s into %s"):format(#fresh, #fresh == 1 and "" or "s", vim.fn.fnamemodify(dir, ":~:.")))
      end
      if #existing > 0 then
        local names = vim.tbl_map(function(f) return vim.fs.basename(f[2]) end, existing)
        require("gv.menu").confirm(("Replace %s?"):format(table.concat(names, ", ")), "Replace", function()
          copy(existing)
          notify(("Replaced %d file%s"):format(#existing, #existing == 1 and "" or "s"))
        end)
      end
    end)
  end)
end

function M.files()
  Snacks.explorer({
    cwd = project_root(),
    title = "Project  ·  U upload  a new  P preview",
    actions = { gv_upload = function(picker) upload(picker) end },
    win = { list = { keys = { ["U"] = "gv_upload" } } },
  })
end

-- Figures: with the cursor on \includegraphics{...} (or right after picking
-- a figure from the completion menu) the figure shows in a popup under it.

local function figure_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local init = 1
  while true do
    local s, e = line:find("\\includegraphics%*?", init)
    if not s then return end
    local i = line:match("^%s*()", e + 1)
    if line:sub(i, i) == "[" then
      local _, close = line:find("%b[]", i)
      if not close then return end
      i = line:match("^%s*()", close + 1)
    end
    if line:sub(i, i) ~= "{" then
      init = e + 1
    else
      local close = line:find("}", i, true)
      if close and col >= s and col <= close + 1 then return vim.trim(line:sub(i + 1, close - 1)) end
      if not close then return end
      init = close + 1
    end
  end
end

-- \graphicspath{{figs/}{img/}} in this file or the main one
local function graphics_dirs(root)
  local dirs = { "" }
  local files = { vim.api.nvim_buf_get_name(0) }
  local ok, main = pcall(vim.fn.eval, "b:vimtex.tex")
  if ok and type(main) == "string" and main ~= "" then files[#files + 1] = main end
  for _, f in ipairs(files) do
    local fd = io.open(f, "r")
    if fd then
      local text = fd:read(20000) or ""
      fd:close()
      local arg = text:match("\\graphicspath%s*(%b{})")
      if arg then for d in arg:sub(2, -2):gmatch("{([^{}]*)}") do dirs[#dirs + 1] = d end end
    end
  end
  return dirs
end

local function find_figure(name)
  local root = project_root()
  local here = vim.fs.dirname(vim.api.nvim_buf_get_name(0))
  local exts = name:match("%.%w+$") and { "" } or { ".pdf", ".png", ".jpg", ".jpeg", ".eps", "" }
  for _, base in ipairs({ root, here }) do
    for _, d in ipairs(graphics_dirs(root)) do
      for _, ext in ipairs(exts) do
        local p = vim.fs.normalize(vim.fs.joinpath(base, d, name .. ext))
        if name:sub(1, 1) == "/" then p = name .. ext end
        if vim.uv.fs_stat(p) and vim.fn.isdirectory(p) == 0 then return p end
      end
    end
  end
end

local fig = {}
local function close_figure()
  if fig.placement then pcall(fig.placement.close, fig.placement) end
  if fig.win and vim.api.nvim_win_is_valid(fig.win) then vim.api.nvim_win_close(fig.win, true) end
  fig = {}
end

local function show_figure()
  local name = figure_at_cursor()
  if not name or name == "" then return close_figure() end
  local file = find_figure(name)
  local key = (file or name) .. vim.api.nvim_win_get_cursor(0)[1]
  if fig.key == key then return end
  close_figure()
  fig.key = key
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local w, h = math.min(56, vim.o.columns - 6), 14
  local text = not file and { "", "  Not found: " .. name, "  (looked next to the main .tex and in \\graphicspath)" } or { "" }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  fig.win = vim.api.nvim_open_win(buf, false, {
    relative = "cursor", row = 1, col = 0, width = w, height = file and h or 3, style = "minimal", border = "rounded",
    focusable = false, zindex = 46, title = { { " \u{f02e9} " .. vim.fn.fnamemodify(file or name, ":t") .. " ", "FloatTitle" } }, title_pos = "left",
  })
  vim.wo[fig.win].winhighlight = "Normal:GvMenu,FloatBorder:GvMenuBorder"
  if not file then return end
  local ok = pcall(function()
    if not Snacks.image.supports_terminal() then error("no images") end
    fig.placement = Snacks.image.placement.new(buf, file, { pos = { 1, 0 }, inline = true, max_width = w, max_height = h })
  end)
  if not ok then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  " .. vim.fn.fnamemodify(file, ":~:."), "  (this terminal can't draw images)" })
    vim.api.nvim_win_set_config(fig.win, { height = 3 })
  end
end

vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
  group = grp,
  callback = function()
    local ft = vim.bo.filetype
    if ft ~= "tex" and ft ~= "plaintex" then return end
    local ok, blink = pcall(require, "blink.cmp")
    if ok and blink.is_visible and blink.is_visible() then return end   -- not over the completion menu
    show_figure()
  end,
})
vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "WinLeave" }, {
  group = grp,
  callback = function()
    if fig.key and not figure_at_cursor() then close_figure() end
  end,
})

-- Export (Overleaf's "Download source"): Space l z puts the project in
-- ~/Downloads/<folder>.zip without LaTeX's build files (.aux, .log, .synctex,
-- ...) and without the compiled PDF, so anyone (or Overleaf) can compile it.
-- Figures that are PDFs stay. An existing zip of that name is kept: the new one gets the time.
local BUILD_FILES = { "*.aux", "*.log", "*.synctex.gz", "*.synctex", "*.fdb_latexmk", "*.fls", "*.out", "*.toc",
  "*.lof", "*.lot", "*.blg", "*.bcf", "*.run.xml", "*.xdv", "*.dvi", "*.glo", "*.gls", "*.glg", "*.acn", "*.acr",
  "*.alg", "*.ist", "*.glsdefs", "*.nav", "*.snm", "*.vrb", "*.swp", "*~", ".git/*", "*/.git/*", ".DS_Store" }

function M.export_zip(outdir)
  local root = project_root()
  outdir = outdir or (vim.fn.isdirectory(vim.fn.expand("~/Downloads")) == 1 and vim.fn.expand("~/Downloads") or vim.fn.expand("~"))
  local name = vim.fs.basename(root)
  local out = outdir .. "/" .. name .. ".zip"
  if vim.uv.fs_stat(out) then out = outdir .. "/" .. name .. os.date("-%Y%m%d-%H%M") .. ".zip" end
  local cmd = { "zip", "-r", "-q", out, ".", "-x" }
  vim.list_extend(cmd, BUILD_FILES)
  local pdf = pdf_path()                                      -- the compiled PDF itself
  if pdf ~= "" then
    local rel = vim.fs.relpath(root, pdf)
    if rel then cmd[#cmd + 1] = rel end
  end
  vim.system(cmd, { cwd = root }, function(r)
    vim.schedule(function()
      if r.code == 0 then
        notify("Saved " .. vim.fn.fnamemodify(out, ":~") .. " (your sources and figures, no build files)")
      else
        notify("zip failed: " .. vim.trim(r.stderr or ""))
      end
    end)
  end)
end

-- Instant maths aliases (tex-auto.json): inside maths they turn into LaTeX the
-- moment you type them, no menu: // -> \frac{}{} (cursor in the numerator, Tab
-- to the denominator), td -> ^{}, sr -> ^2, ;a -> \alpha, oo -> \infty, ...
-- Letter triggers only fire at the start of a word and never after _ ^ { or a
-- letter, so \sigma_{xx}, t_{pd} and words like "effect" stay as typed.
-- Space u a switches them off / on.
M.auto = true
local auto_list
local function load_auto()
  auto_list = {}
  local fd = io.open(vim.fn.stdpath("config") .. "/tex-auto.json", "r")
  if not fd then return end
  local ok, data = pcall(vim.json.decode, fd:read("*a"))
  fd:close()
  for trig, a in pairs(ok and data or {}) do auto_list[#auto_list + 1] = { trig = trig, body = a.body } end
  table.sort(auto_list, function(x, y) return #x.trig > #y.trig end)   -- longest first ("..." before "..")
end

local function in_math()
  local ok, r = pcall(vim.fn["vimtex#syntax#in_mathzone"])
  return ok and r == 1
end

local POWER = { sr = true, cb = true, td = true, inv = true }
local expanding = false
local function auto_expand()
  if not M.auto or expanding then return end
  if not auto_list then load_auto() end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local before = vim.api.nvim_get_current_line():sub(1, col)
  for _, a in ipairs(auto_list) do
    local t = a.trig
    if #before >= #t and before:sub(-#t) == t then
      local rest = before:sub(1, -#t - 1)
      local prev = rest:sub(-1)
      local word_ok
      if POWER[t] then
        -- x sr -> x^2 and xsr -> x^2, but not while typing a \command or inside _{ } / ^{ }
        word_ok = not (rest .. t):match("\\%a*$") and not rest:match("[_^]{[%w]*$") and not prev:match("[_^]")
      elseif t:match("^%a") then
        word_ok = not prev:match("[%w{_\\}]")           -- start of a word (^oo ok), not an index (_xx, {xx})
      else
        word_ok = prev ~= "\\"
      end
      if word_ok and in_math() then
        expanding = true
        vim.api.nvim_buf_set_text(0, row - 1, col - #t, row - 1, col, {})
        vim.api.nvim_win_set_cursor(0, { row, col - #t })
        vim.snippet.expand(a.body)
        vim.schedule(function() expanding = false end)
        return
      end
    end
  end
end

vim.api.nvim_create_autocmd("TextChangedI", {
  group = grp,
  callback = function()
    local ft = vim.bo.filetype
    if ft == "tex" or ft == "plaintex" then auto_expand() end
  end,
})

function M.toggle_auto()
  M.auto = not M.auto
  notify(M.auto and "Instant maths aliases on (// td sr ;a ...)" or "Instant maths aliases off")
end

function M.toggle_grammar()
  M.grammar = not M.grammar
  vim.lsp.enable("ltex_plus", M.grammar)      -- off also stops it (frees its memory)
  if M.grammar then
    notify("Grammar check on (LanguageTool): the first check takes a few seconds")
  else
    notify("Grammar check off")
  end
end

return M
