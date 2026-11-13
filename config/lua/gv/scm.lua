-- Source Control card: VS Code's Source Control view as a floating Material card.
-- Open: Space G, "Source control…" in the git menu, a click on the +/~/- counts
-- in the status line, or G on the start screen.
--
--   ╭─ 󰊢 Source Control ─────────────╮
--   │ Message (Enter to commit)      │   ← c jumps here; Enter commits
--   ╰────────────────────────────────╯
--   ╭────────────────────────────────╮
--   │   main  ↑1                    │
--   │  ✓ Commit   󰓦 Sync   ⋯ More   │   ← click, or C / S / ?
--   │ ▾ STAGED CHANGES 1           − │
--   │    M calc.py               −   │
--   │ ▾ CHANGES 2                  + │
--   │    M config  i3/         󰕌 +   │   ← click 󰕌 discard, + stage; Enter opens
--   ╰────────────────────────────────╯
-- On a file: Enter open · d diff · s stage · u unstage · x discard.   Esc / q closes.
local git = require("gv.git")
local menu = require("gv.menu")
local M = {}
local ns = vim.api.nvim_create_namespace("gv_scm")
local W = 52
local st = { collapsed = {} }      -- msg_win, msg_buf, win, buf, root, rows, return_win, saved_cursor

local CODE_HL = { M = "GvModified", A = "GvAdded", D = "GvDeleted", R = "GvModified", ["?"] = "GvUntracked", U = "GvDeleted" }

local function is_open() return st.win and vim.api.nvim_win_is_valid(st.win) end
local function dw(s) return vim.fn.strdisplaywidth(s) end

function M.close()
  if not st.win then return end
  for _, w in ipairs({ st.win, st.msg_win }) do
    if w and vim.api.nvim_win_is_valid(w) then vim.api.nvim_win_close(w, true) end
  end
  st.win, st.msg_win = nil, nil
  if st.saved_cursor then vim.o.guicursor = st.saved_cursor; st.saved_cursor = nil end
  if st.augroup then pcall(vim.api.nvim_del_augroup_by_id, st.augroup); st.augroup = nil end
  if st.return_win and vim.api.nvim_win_is_valid(st.return_win) then pcall(vim.api.nvim_set_current_win, st.return_win) end
end

local function message() return vim.trim(table.concat(vim.api.nvim_buf_get_lines(st.msg_buf, 0, -1, false), "\n")) end

local function do_commit()
  local s = git.get(st.root)
  local msg = message()
  if msg == "" then
    vim.notify("Write a commit message first (press c)", vim.log.levels.WARN, { title = "Git" })
    return M.focus_message()
  end
  local root = st.root
  local function go(stage_all)
    git.commit(root, msg, stage_all, function(r)
      if r.code == 0 and st.msg_buf and vim.api.nvim_buf_is_valid(st.msg_buf) then
        vim.api.nvim_buf_set_lines(st.msg_buf, 0, -1, false, { "" })
        if st.placeholder then st.placeholder() end
      end
    end)
    -- back to the card, so S / P / q work right away
    vim.cmd.stopinsert()
    vim.schedule(function() if is_open() then vim.api.nvim_set_current_win(st.win) end end)
  end
  if s and #s.staged > 0 then return go(false) end
  if not s or #s.changes == 0 then return vim.notify("Nothing to commit", vim.log.levels.INFO, { title = "Git" }) end
  menu.confirm("Nothing is staged", "Stage all changes and commit", function() go(true) end)
end

local function actions()
  local root = st.root
  return {
    commit = do_commit,
    sync = function() git.sync(root) end,
    more = function() require("gv.gitmenu").open({ relative = "editor", row = 4, col = math.max(0, vim.o.columns - W - 42) }) end,
  }
end

-- build the card's text, highlights, and what each row / click does
local function render(s)
  local lines, hls, rows = {}, {}, {}
  local inner = W
  local function add(text, row, spans)
    lines[#lines + 1] = text
    rows[#lines] = row or {}
    for _, sp in ipairs(spans or {}) do hls[#hls + 1] = { #lines - 1, sp[1], sp[2], sp[3] } end
  end
  local head = "\u{e725} " .. s.branch .. (s.ahead > 0 and ("  ↑" .. s.ahead) or "") .. (s.behind > 0 and ("  ↓" .. s.behind) or "")
  add(" " .. head, {}, { { 1, 1 + #head, "GvSection" } })

  -- buttons (pills)
  local a = actions()
  local btns = { { " ✓ Commit ", "GvButtonPrimary", a.commit }, { (" \u{f04e6} Sync ↓%d ↑%d "):format(s.behind, s.ahead), "GvButton", a.sync },
    { " ⋯ More ", "GvButton", a.more } }
  local text, spans, clicks, col = " ", {}, {}, 1
  for _, b in ipairs(btns) do
    spans[#spans + 1] = { #text, #text + #b[1], b[2] }
    clicks[#clicks + 1] = { col + 1, col + dw(b[1]), b[3] }
    text = text .. b[1] .. "  "
    col = col + dw(b[1]) + 2
  end
  add(text, { clicks = clicks }, spans)
  add("", {})

  local function section(key, title, list, staged)
    local collapsed = st.collapsed[key]
    local left = (collapsed and " ▸ " or " ▾ ") .. title .. " "
    local badge = " " .. #list .. " "
    local right = staged and "−" or "+"
    local pad = inner - dw(left) - dw(badge) - dw(right) - 2
    local line = left .. badge .. string.rep(" ", math.max(1, pad)) .. right .. " "
    local rcol = dw(left) + dw(badge) + math.max(1, pad) + 1
    local all = staged and function() git.unstage(st.root) end or function() git.stage(st.root) end
    add(line, { header = key, clicks = { { rcol, rcol, all } } },
      { { 0, #left, "GvSection" }, { #left, #left + #badge, "GvBadge" }, { #line - 1 - #right, #line - 1, "GvAction" } })
    if collapsed then return end
    if #list == 0 then add("     nothing here", {}, { { 0, -1, "GvMenuDim" } }) end
    for _, f in ipairs(list) do
      local name = vim.fs.basename(f.path)
      local dir = vim.fs.dirname(f.path)
      dir = dir == "." and "" or dir
      local acts = staged and "−" or "\u{f054c}  +"
      local leftf = "    " .. f.code .. "  " .. name .. (dir ~= "" and ("  " .. dir) or "")
      local room = inner - dw(acts) - 3
      if dw(leftf) > room then leftf = vim.fn.strcharpart(leftf, 0, room - 1) .. "…" end
      local l = leftf .. string.rep(" ", room - dw(leftf)) .. "  " .. acts .. " "
      local acol = room + 3                                   -- display column of the first action
      local fclicks = staged and { { acol, acol, function() git.unstage(st.root, f.path) end } }
        or { { acol, acol, function() M.discard(f) end }, { acol + 3, acol + 3, function() git.stage(st.root, f.path) end } }
      local nstart = 4 + #f.code + 2
      add(l, { file = f, staged = staged, clicks = fclicks }, {
        { 4, 4 + #f.code, CODE_HL[f.code] or "GvModified" },
        { nstart + #name, nstart + #name + (dir ~= "" and #dir + 2 or 0), "GvMenuDim" },
        { #l - 1 - #acts, #l - 1, "GvAction" },
      })
    end
  end
  section("staged", "STAGED CHANGES", s.staged, true)
  section("changes", "CHANGES", s.changes, false)
  return lines, hls, rows
end

local function draw()
  if not is_open() then return end
  local s = git.get(st.root)
  if not s then return end
  local lines, hls, rows = render(s)
  st.rows = rows
  vim.bo[st.buf].modifiable = true
  vim.api.nvim_buf_set_lines(st.buf, 0, -1, false, lines)
  vim.bo[st.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(st.buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    local len = #lines[h[1] + 1]
    vim.api.nvim_buf_set_extmark(st.buf, ns, h[1], math.min(h[2], len), { end_col = (h[3] < 0 or h[3] > len) and len or h[3], hl_group = h[4] })
  end
  local height = math.min(#lines, vim.o.lines - 10)
  vim.api.nvim_win_set_config(st.win, { height = height })
  local row = math.min(vim.api.nvim_win_get_cursor(st.win)[1], #lines)
  vim.api.nvim_win_set_cursor(st.win, { row, 0 })
end

function M.discard(f)
  menu.confirm(f.code == "?" and ("Delete " .. f.path .. "?") or ("Discard changes to " .. f.path .. "?"),
    f.code == "?" and "Delete" or "Discard", function() git.discard(st.root, f) end)
end

local function row_here() return st.rows[vim.api.nvim_win_get_cursor(st.win)[1]] or {} end

local function open_here(diff)
  local r = row_here()
  if r.header then st.collapsed[r.header] = not st.collapsed[r.header]; return draw() end
  if not r.file then return end
  local root, f, staged = st.root, r.file, r.staged
  M.close()
  git.open_file(root, f, diff, staged)
end

function M.focus_message()
  if st.msg_win and vim.api.nvim_win_is_valid(st.msg_win) then
    vim.api.nvim_set_current_win(st.msg_win)
    vim.cmd.startinsert({ bang = true })
  end
end

function M.open()
  if is_open() then return vim.api.nvim_set_current_win(st.win) end
  local root = git.root()
  if not root then return require("gv.gitmenu").open("center") end
  st.root, st.return_win = root, git.edit_window()
  local col, row = vim.o.columns - W - 4, 1

  -- the commit message box
  st.msg_buf = (st.msg_buf and vim.api.nvim_buf_is_valid(st.msg_buf)) and st.msg_buf or vim.api.nvim_create_buf(false, true)
  vim.bo[st.msg_buf].filetype = "gitcommit"
  st.msg_win = vim.api.nvim_open_win(st.msg_buf, false, {
    relative = "editor", row = row, col = col, width = W, height = 1, style = "minimal", border = "rounded", zindex = 60,
    title = { { " \u{f02a2} Source Control ", "FloatTitle" } }, title_pos = "left",
  })
  vim.wo[st.msg_win].winhighlight = "Normal:GvMenu,FloatBorder:SnacksInputBorder"
  local function placeholder()
    vim.api.nvim_buf_clear_namespace(st.msg_buf, ns, 0, -1)
    if message() == "" then
      vim.api.nvim_buf_set_extmark(st.msg_buf, ns, 0, 0, { virt_text = { { "Message (Enter to commit · c to type)", "GvPlaceholder" } }, virt_text_pos = "overlay" })
    end
  end
  placeholder()
  st.placeholder = placeholder
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, { buffer = st.msg_buf, callback = placeholder })

  -- the card with buttons and files
  st.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[st.buf].filetype, vim.bo[st.buf].bufhidden = "gvscm", "wipe"
  st.win = vim.api.nvim_open_win(st.buf, true, {
    relative = "editor", row = row + 3, col = col, width = W, height = 4, style = "minimal", border = "rounded", zindex = 60,
    footer = { { " ⏎ open · d diff · s/u stage · x discard ", "FloatFooter" } }, footer_pos = "center",
  })
  vim.wo[st.win].winhighlight = "Normal:GvMenu,FloatBorder:GvMenuBorder,CursorLine:GvMenuSel"
  vim.wo[st.win].cursorline = true
  st.saved_cursor = vim.o.guicursor

  -- keys in the card
  local function map(lhs, fn, buf, mode) vim.keymap.set(mode or "n", lhs, fn, { buffer = buf or st.buf, nowait = true, silent = true }) end
  local a = actions()
  map("<CR>", function() open_here(false) end)
  map("o", function() open_here(false) end)
  map("<2-LeftMouse>", function() open_here(false) end)
  map("d", function() open_here(true) end)
  map("s", function() local r = row_here(); if r.file then git.stage(st.root, r.file.path) else git.stage(st.root) end end)
  map("u", function() local r = row_here(); if r.file then git.unstage(st.root, r.file.path) else git.unstage(st.root) end end)
  map("x", function() local r = row_here(); if r.file and not r.staged then M.discard(r.file) end end)
  map("c", M.focus_message)
  map("i", M.focus_message)
  map("C", a.commit)
  map("S", a.sync)
  map("P", function() git.push(st.root) end)
  map("p", function() git.pull(st.root) end)
  map("?", a.more)
  map("r", function() git.status(st.root) end)
  for _, k in ipairs({ "q", "<Esc>" }) do map(k, M.close) end
  map("<LeftRelease>", function()
    local m = vim.fn.getmousepos()
    if m.winid ~= st.win then return end
    for _, c in ipairs((st.rows[m.line] or {}).clicks or {}) do
      if m.wincol >= c[1] and m.wincol <= c[2] then return c[3]() end
    end
  end)
  -- keys in the message box
  map("<CR>", do_commit, st.msg_buf, { "n", "i" })
  map("<Esc>", function() vim.api.nvim_set_current_win(st.win) end, st.msg_buf)
  map("<Tab>", function() vim.cmd.stopinsert(); vim.api.nvim_set_current_win(st.win) end, st.msg_buf, { "n", "i" })
  map("<Down>", function() vim.api.nvim_set_current_win(st.win) end, st.msg_buf)

  -- hidden cursor in the card, normal cursor in the message box; close when you leave
  st.augroup = vim.api.nvim_create_augroup("gv_scm", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = st.augroup,
    callback = function()
      local w = vim.api.nvim_get_current_win()
      if w == st.win then vim.o.guicursor = "a:GvHiddenCursor"
      elseif w == st.msg_win then vim.o.guicursor = st.saved_cursor
      elseif vim.bo[vim.api.nvim_win_get_buf(w)].filetype ~= "gvmenu" then
        vim.schedule(function() st.return_win = nil; M.close() end)
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", { group = st.augroup, pattern = "GvGitStatus", callback = draw })
  vim.api.nvim_create_autocmd("VimResized", { group = st.augroup, callback = function() M.close() end })
  vim.o.guicursor = "a:GvHiddenCursor"
  git.status(root, function() draw(); if is_open() then vim.api.nvim_win_set_cursor(st.win, { math.min(4, #st.rows), 0 }) end end)
end

function M.toggle() if is_open() then M.close() else M.open() end end
return M
