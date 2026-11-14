-- A small Material dropdown menu (used by the git menu, and for confirmations).
--
--   require("gv.menu").open({
--     title = "Git",                       -- optional pill at the top
--     anchor = "statusline" | "cursor" | "center" | { row = .., col = .. },
--     items = {
--       { icon = "\u{f012c}", label = "Commit…", key = "c", run = function() ... end },
--       "-",                                -- a separator
--       { icon = "\u{f0214}", label = "Files", submenu = function() return { items = {...} } end },
--       { label = "Nothing to push", disabled = true },
--     },
--   })
--
-- Keys: j/k or arrows move, Enter / l / click runs, the letter on the right runs
-- that item, h / Backspace goes back from a submenu, Esc / q or a click outside closes.
local M = {}
local ns = vim.api.nvim_create_namespace("gv_menu")
local cur = nil                             -- the open menu: { win, buf, opts, rows, saved_cursor }

local function selectable(it) return type(it) == "table" and not it.disabled end

local function close()
  if not cur then return end
  local c = cur
  cur = nil
  if c.saved_cursor then vim.o.guicursor = c.saved_cursor end
  if vim.api.nvim_win_is_valid(c.win) then vim.api.nvim_win_close(c.win, true) end
  if c.return_win and vim.api.nvim_win_is_valid(c.return_win) then pcall(vim.api.nvim_set_current_win, c.return_win) end
end
M.close = close

local function layout(opts)
  local rows, width = {}, 0
  for _, it in ipairs(opts.items) do
    if it == "-" then
      rows[#rows + 1] = { sep = true }
    else
      local right = it.submenu and "›" or (it.key or "")
      local left = ("%s  %s"):format(it.icon or " ", it.label)
      rows[#rows + 1] = { item = it, left = left, right = right }
      width = math.max(width, vim.fn.strdisplaywidth(left) + vim.fn.strdisplaywidth(right) + 4)
    end
  end
  width = math.max(width + 2, opts.min_width or 24, opts.title and vim.fn.strdisplaywidth(opts.title) + 6 or 0)
  local lines = {}
  for i, r in ipairs(rows) do
    if r.sep then
      lines[i] = " " .. string.rep("─", width - 2) .. " "
    else
      local gap = width - 2 - vim.fn.strdisplaywidth(r.left) - vim.fn.strdisplaywidth(r.right)
      lines[i] = " " .. r.left .. string.rep(" ", gap) .. r.right .. " "
    end
  end
  return rows, lines, width
end

local function position(anchor, width, height)
  if type(anchor) == "table" then return vim.tbl_extend("keep", anchor, { relative = "editor" }) end
  if anchor == "cursor" then return { relative = "cursor", row = 1, col = 0 } end
  if anchor == "center" then
    return { relative = "editor", row = math.floor((vim.o.lines - height) / 2) - 1, col = math.floor((vim.o.columns - width) / 2) }
  end
  -- "statusline": just above the bottom-left of the status line, like VS Code's status bar menus
  return { relative = "editor", anchor = "SW", row = vim.o.lines - 2, col = 1 }
end

local function move(dir)
  local row = vim.api.nvim_win_get_cursor(cur.win)[1]
  local n = #cur.rows
  for _ = 1, n do
    row = (row - 1 + dir) % n + 1
    if cur.rows[row].item and selectable(cur.rows[row].item) then break end
  end
  vim.api.nvim_win_set_cursor(cur.win, { row, 0 })
end

local function activate(row)
  if not cur then return end
  row = row or vim.api.nvim_win_get_cursor(cur.win)[1]
  local r = cur.rows[row]
  if not (r and r.item and selectable(r.item)) then return end
  local it, opts = r.item, cur.opts
  if it.submenu then
    local sub = it.submenu()
    sub.anchor, sub.parent, sub.return_win = sub.anchor or opts.anchor, opts, opts.return_win
    sub.title = sub.title or it.label
    close()
    return M.open(sub)
  end
  close()
  if it.run then vim.schedule(it.run) end
end

function M.open(opts)
  close()
  opts.return_win = opts.return_win or vim.api.nvim_get_current_win()
  local rows, lines, width = layout(opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable, vim.bo[buf].filetype, vim.bo[buf].bufhidden = false, "gvmenu", "wipe"

  for i, r in ipairs(rows) do
    if r.sep then
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = #lines[i], hl_group = "GvMenuSep" })
    else
      local icon_end = 1 + #(r.item.icon or " ")
      if r.item.disabled then
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = #lines[i], hl_group = "GvMenuDim" })
      else
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 1, { end_col = icon_end, hl_group = r.item.icon_hl or "GvMenuIcon" })
        local rstart = #lines[i] - 1 - #r.right
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, rstart, { end_col = #lines[i] - 1, hl_group = "GvMenuKey" })
      end
    end
  end

  local pos = position(opts.anchor, width, #lines)
  local win = vim.api.nvim_open_win(buf, true, vim.tbl_extend("force", pos, {
    width = width, height = #lines, style = "minimal", border = "rounded", zindex = 70,
    title = opts.title and { { " " .. opts.title .. " ", "FloatTitle" } } or nil, title_pos = opts.title and "left" or nil,
  }))
  vim.wo[win].winhighlight = "Normal:GvMenu,FloatBorder:GvMenuBorder,CursorLine:GvMenuSel"
  vim.wo[win].cursorline = true
  cur = { win = win, buf = buf, opts = opts, rows = rows, return_win = opts.return_win, saved_cursor = vim.o.guicursor }
  vim.o.guicursor = "a:GvHiddenCursor"      -- no blinking cursor block inside the menu

  -- start on the first item you can choose
  for i, r in ipairs(rows) do
    if r.item and selectable(r.item) then vim.api.nvim_win_set_cursor(win, { i, 0 }); break end
  end

  local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true }) end
  for _, k in ipairs({ "j", "<Down>", "<Tab>", "<ScrollWheelDown>" }) do map(k, function() move(1) end) end
  for _, k in ipairs({ "k", "<Up>", "<S-Tab>", "<ScrollWheelUp>" }) do map(k, function() move(-1) end) end
  for _, k in ipairs({ "<CR>", "l", "<Right>", "<Space>" }) do map(k, function() activate() end) end
  for _, k in ipairs({ "<Esc>", "q" }) do map(k, close) end
  for _, k in ipairs({ "h", "<Left>", "<BS>" }) do
    map(k, function()
      local parent = cur.opts.parent
      close()
      if parent then M.open(parent) end
    end)
  end
  map("<LeftRelease>", function()
    local m = vim.fn.getmousepos()
    if m.winid == win then activate(m.line) else close() end
  end)
  for i, r in ipairs(rows) do
    local k = r.item and r.item.key
    if k and #k == 1 and not k:match("[jkhlq]") then map(k, function() activate(i) end) end
  end
  -- a click anywhere else (or moving to another window) closes the menu
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf, once = true,
    callback = function() vim.schedule(function() if cur and cur.win == win then cur.return_win = nil; close() end end) end,
  })
end

-- a yes / no question as a menu (centered); on_yes runs on "yes"
function M.confirm(question, yes_label, on_yes)
  M.open({
    title = question, anchor = "center",
    items = {
      { icon = "\u{f01b4}", label = yes_label, key = "y", run = on_yes, icon_hl = "GvDeleted" },
      { icon = "\u{f0156}", label = "Cancel", key = "n" },
    },
  })
end

return M
